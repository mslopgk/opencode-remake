#!/usr/bin/env bash
# 새 제공자(Cloudflare·fal) 연동 테스트.
# 진짜 API 를 부르지 않는다. 진짜 '응답 모양' 을 흉내낸 서버를 상대로 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

S="$REPO/scripts/camp-media.sh"
TMP="$(mktemp -d)"

PY=""
for c in python py python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then PY="$c"; break; fi
done
"$PY" "$REPO/tests/mock/fake-api.py" > "$TMP/port" 2>/dev/null &
SRV=$!
trap 'kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT

# 서버가 뜰 때까지 기다린다
PORT=""
for _ in $(seq 1 50); do
  PORT="$(head -1 "$TMP/port" 2>/dev/null)"
  [ -n "$PORT" ] && break
  sleep 0.2
done
if [ -z "$PORT" ]; then fail "시험용 서버가 뜨지 않음"; summary; exit 1; fi
pass "시험용 서버 준비 ($PORT)"

BASE="http://127.0.0.1:$PORT"
export CF_API_BASE="$BASE" FAL_QUEUE_BASE="$BASE" CAMP_MEDIA_POLL_SEC=0.2
export CAMP_MEDIA_KEYS="$TMP/none.env"

TEAM="$TMP/03조_지구지킴이"; mkdir -p "$TEAM/assets"

# --- 1) 열쇠가 없으면 만들지 않고 6 으로 끝난다 ---
( unset CF_ACCOUNT_ID CF_API_TOKEN
  bash "$S" --kind 그림 --prompt "ocean" --team-dir "$TEAM" >/dev/null 2>&1 )
assert_eq "$?" "6" "열쇠가 없으면 exit 6"
assert_eq "$(ls "$TEAM/assets" | wc -l)" "0" "열쇠가 없으면 파일도 안 만듦"

# 진짜 열쇠는 ASCII 다. 시험도 그렇게 한다.
export CF_ACCOUNT_ID="abc123account" CF_API_TOKEN="testtoken" FAL_KEY="testfalkey"

# --- 2) 그림: Cloudflare 로 진짜 PNG 를 받아 저장한다 ---
OUT="$(bash "$S" --kind 그림 --prompt "clean ocean illustration" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "그림 생성 성공"
assert_eq "$OUT" "assets/그림-1.png" "상대경로 출력"
assert_file "$TEAM/$OUT" "그림 파일이 생김"
HDR="$(head -c 4 "$TEAM/$OUT" | od -An -tx1 | tr -d ' \n')"
assert_eq "$HDR" "89504e47" "base64 를 풀어 진짜 PNG 로 저장"

# --- 3) 대표도 Cloudflare 를 쓴다 (더 이상 비싼 모델이 아니다) ---
OUT2="$(bash "$S" --kind 대표 --prompt "campaign poster" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "대표 생성 성공"
assert_file "$TEAM/$OUT2" "대표 파일이 생김"

# --- 4) 영상: fal 큐를 기다렸다가 내려받는다 ---
OUT3="$(bash "$S" --kind 영상 --prompt "ocean cleanup" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "영상 생성 성공"
assert_eq "$OUT3" "assets/영상-1.mp4" "영상 상대경로"
assert_contains "$(head -c 12 "$TEAM/$OUT3")" "ftyp" "진짜 mp4 를 받아 저장"

# --- 5) 횟수는 제한하지 않는다 (주최측 결정) ---
for i in b c d e; do
  bash "$S" --kind 영상 --prompt "$i" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "영상 5편째도 막지 않음"
bash "$S" --kind 대표 --prompt "many" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "대표 그림도 막지 않음"

# --- 5b) 대신 모델과 길이는 고정한다 (편당 상한이 곧 길이다) ---
SRC5="$(cat "$S")"
assert_contains "$SRC5" 'SECS=5' "영상 길이가 5초로 고정"
assert_contains "$SRC5" '--seconds "$SECS"' "고정한 길이를 실제로 넘김"

# --- 5c) 쓴 만큼 기록이 남는다 (막지 않는 대신 보이게 한다) ---
assert_file "$TEAM/.camp/usage.log" "사용 기록 파일이 생김"
assert_contains "$(cat "$TEAM/.camp/usage.log")" "영상" "영상 사용이 기록됨"
assert_contains "$(cat "$TEAM/.camp/usage.log")" "0.400" "영상 단가가 기록됨"

# --- 6) 실패하면 횟수를 올리지 않는다 (돈이 안 나갔으니까) ---
T2="$TMP/04조"; mkdir -p "$T2/assets"
( export CF_API_TOKEN="wrongtoken"
  bash "$S" --kind 대표 --prompt "x" --team-dir "$T2" >/dev/null 2>&1 )
RC=$?
if [ "$RC" -ne 0 ]; then pass "열쇠가 틀리면 실패로 끝남"; else fail "틀린 열쇠인데 성공함"; fi
COUNTS="$(cat "$T2/.camp/counts" 2>/dev/null || true)"
assert_not_contains "$COUNTS" "대표=" "실패는 횟수에 안 셈"
assert_eq "$(ls "$T2/assets" | wc -l)" "0" "실패하면 빈 파일을 남기지 않음"

# --- 7) 단가가 싼 쪽으로 옮겨졌는지 (문서가 아니라 코드로 확인) ---
SRC="$(cat "$S")"
assert_contains "$SRC" "flux-1-schnell" "그림은 Cloudflare FLUX"
assert_contains "$SRC" "minimax/h3/text-to-video" "영상은 fal MiniMax H3"
assert_not_contains "$SRC" "nano_banana" "비싼 Higgsfield 그림 모델을 더 쓰지 않음"
assert_not_contains "$SRC" "gpt_image_2" "비싼 Higgsfield 대표 모델을 더 쓰지 않음"
assert_not_contains "$SRC" "seedance" "비싼 Higgsfield 영상 모델을 더 쓰지 않음"

# --- 8) 가짜 python3 함정 (Windows 에서 실제로 걸렸다) ---
assert_not_contains "$SRC" 'command -v python3 || command -v python' "이름만 보고 python3 를 고르지 않음"
assert_contains "$SRC" '-c "pass"' "실제로 실행되는지 확인하고 고름"

# --- 9) 열쇠가 깨져 있으면 학생이 읽을 수 있는 말로 알려 준다 ---
T3="$TMP/05조"; mkdir -p "$T3/assets"
OUT9="$( export CF_API_TOKEN="깨진열쇠"
  bash "$S" --kind 그림 --prompt "x" --team-dir "$T3" 2>&1 )"
assert_contains "$OUT9" "선생님" "깨진 열쇠는 사람 말로 안내"
assert_not_contains "$OUT9" "codec" "파이썬 오류를 그대로 보여주지 않음"

summary
