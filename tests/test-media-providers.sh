#!/usr/bin/env bash
# 비상 경로(Cloudflare · fal) 연동 테스트.
#
# 평소에는 전부 Higgsfield 로 만든다. 이 파일은 Higgsfield 가 막혔을 때
# 쓰는 경로가 살아 있는지 본다. 그래서 제공자를 반드시 명시한다 —
# 명시하지 않으면 기본값(Higgsfield)으로 진짜 API 를 부른다(실제로 겪었다).
#
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
# 이 파일의 모든 호출은 비상 경로를 향한다
export CAMP_MEDIA_PROVIDER=fal
export CAMP_MEDIA_KEYS="$TMP/none.env"

sent_input() { curl -fsS "$BASE/last-input" 2>/dev/null; }

TEAM="$TMP/03조_지구지킴이"; mkdir -p "$TEAM/assets"

# --- 1) 열쇠가 없으면 만들지 않고 6 으로 끝난다 ---
( unset FAL_KEY CF_ACCOUNT_ID CF_API_TOKEN
  bash "$S" --kind 그림 --prompt "ocean" --team-dir "$TEAM" >/dev/null 2>&1 )
assert_eq "$?" "6" "열쇠가 없으면 exit 6"
assert_eq "$(ls "$TEAM/assets" | wc -l)" "0" "열쇠가 없으면 파일도 안 만듦"

export FAL_KEY="testfalkey" CF_ACCOUNT_ID="abc123account" CF_API_TOKEN="testtoken"

# --- 2) 그림: Nano Banana 2 로 진짜 PNG 를 받아 저장한다 ---
OUT="$(bash "$S" --kind 그림 --prompt "clean ocean illustration" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "그림 생성 성공"
assert_eq "$OUT" "assets/그림-1.jpg" "상대경로 출력"
HDR="$(head -c 4 "$TEAM/$OUT" | od -An -tx1 | tr -d ' \n')"
assert_eq "$HDR" "89504e47" "진짜 PNG 로 저장"

IN="$(sent_input)"
assert_contains "$IN" "clean ocean illustration" "프롬프트를 그대로 보냄"
assert_contains "$IN" '"resolution": "1K"' "그림은 1K"
assert_contains "$IN" '"aspect_ratio": "16:9"' "발표 화면에 맞는 16:9"

# --- 3) 대표는 같은 모델을 2K 로 (프로젝터에 꽉 차게 나온다) ---
OUT2="$(bash "$S" --kind 대표 --prompt "campaign poster" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "대표 생성 성공"
IN2="$(sent_input)"
assert_contains "$IN2" '"resolution": "1K"' "비상 경로는 해상도도 고정"

# --- 4) 영상: 큐를 기다렸다가 내려받는다. 길이는 고정 ---
OUT3="$(bash "$S" --kind 영상 --prompt "ocean cleanup" --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "영상 생성 성공"
assert_eq "$OUT3" "assets/영상-1.mp4" "영상 상대경로"
assert_contains "$(head -c 12 "$TEAM/$OUT3")" "ftyp" "진짜 mp4 를 받아 저장"
IN3="$(sent_input)"
assert_contains "$IN3" '"duration": 5' "영상 길이가 5초로 고정"

# --- 5) 횟수는 제한하지 않는다 (주최측 결정) ---
for i in b c d e; do
  bash "$S" --kind 영상 --prompt "$i" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "영상 5편째도 막지 않음"
bash "$S" --kind 대표 --prompt "many" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "대표 그림도 막지 않음"

# --- 6) 쓴 만큼 기록이 남는다 (막지 않는 대신 보이게 한다) ---
assert_file "$TEAM/.camp/usage.log" "사용 기록 파일이 생김"
# 기록은 크레딧 단위다 (평소 제공자가 Higgsfield 이므로)
LOG="$(cat "$TEAM/.camp/usage.log")"
assert_contains "$LOG" "영상" "영상 사용이 기록됨"
assert_contains "$LOG" "그림" "그림 사용이 기록됨"
assert_contains "$LOG" "대표" "대표 사용이 기록됨"

# --- 7) 실패는 기록하지 않는다 (돈이 안 나갔으니까) ---
T2="$TMP/04조"; mkdir -p "$T2/assets"
( export FAL_QUEUE_BASE="http://127.0.0.1:1"      # 아무도 안 듣는 포트
  bash "$S" --kind 대표 --prompt "x" --team-dir "$T2" >/dev/null 2>&1 )
RC=$?
if [ "$RC" -ne 0 ]; then pass "연결이 안 되면 실패로 끝남"; else fail "연결이 안 되는데 성공함"; fi
COUNTS="$(cat "$T2/.camp/counts" 2>/dev/null || true)"
assert_not_contains "$COUNTS" "대표=" "실패는 기록에 안 넣음"
assert_eq "$(ls "$T2/assets" | wc -l)" "0" "실패하면 빈 파일을 남기지 않음"

# --- 8) 비상 경로: fal 이 막히면 Cloudflare 로 넘어갈 수 있다 ---
T3="$TMP/05조"; mkdir -p "$T3/assets"
OUT8="$( export CAMP_MEDIA_PROVIDER=cloudflare
         bash "$S" --kind 그림 --prompt "backup path" --team-dir "$T3" 2>&1 )"
assert_eq "$?" "0" "Cloudflare 비상 경로가 살아 있음"
HDR8="$(head -c 4 "$T3/$OUT8" | od -An -tx1 | tr -d ' \n')"
assert_eq "$HDR8" "89504e47" "비상 경로도 진짜 PNG"

# --- 9) 모델·해상도·길이가 코드에 고정돼 있다 ---
SRC="$(cat "$S")"
assert_contains "$SRC" "fal-ai/nano-banana-2" "그림은 Nano Banana 2"
assert_contains "$SRC" "minimax/h3/text-to-video" "영상은 MiniMax H3"
assert_contains "$SRC" '"duration":5' "영상 길이 고정"
assert_not_contains "$SRC" "gpt_image_2" "비싼 Higgsfield 모델을 쓰지 않음"
assert_not_contains "$SRC" "seedance" "비싼 Higgsfield 영상 모델을 쓰지 않음"

# --- 10) 가짜 python3 함정 (Windows 에서 실제로 걸렸다) ---
assert_not_contains "$SRC" 'command -v python3 || command -v python' "이름만 보고 python3 를 고르지 않음"
assert_contains "$SRC" '-c "pass"' "실제로 실행되는지 확인하고 고름"

# --- 11) 열쇠가 깨져 있으면 학생이 읽을 수 있는 말로 알려 준다 ---
T4="$TMP/06조"; mkdir -p "$T4/assets"
OUT11="$( export FAL_KEY="깨진열쇠"
          bash "$S" --kind 그림 --prompt "x" --team-dir "$T4" 2>&1 )"
assert_contains "$OUT11" "선생님" "깨진 열쇠는 사람 말로 안내"
assert_not_contains "$OUT11" "codec" "파이썬 오류를 그대로 보여주지 않음"

# --- 12) 파이썬 메시지가 UTF-8 로 나와야 한다 ---
# 실측 사고: Windows 파이썬이 stderr 를 cp949 로 써서 "열쇠가 없어요" 를
# 셸이 못 잡았다. 그래서 exit 6 이 절대 안 나오고 늘 5 였다.
# 학생에게는 "재료가 다 떨어졌어요" 대신 엉뚱한 안내가 갔을 것이다.
SRC12="$(cat "$REPO/scripts/media-gen.py")"
assert_contains "$SRC12" 'encoding="utf-8"' "media-gen.py 가 출력 인코딩을 고정"
assert_contains "$SRC12" "TextIOWrapper" "stdout·stderr 를 감싼다"
SH12="$(cat "$S")"
assert_contains "$SH12" "PYTHONIOENCODING=utf-8" "셸에서도 한 번 더 고정"

summary
