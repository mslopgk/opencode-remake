#!/usr/bin/env bash
# camp-media.sh 단위 테스트 — 제한·이름짓기·인자 검증.
# 실제 제공자 호출은 test-media-providers.sh 가 가짜 서버로 검증한다.
# 여기서는 CAMP_MEDIA_FAKE_DOWNLOAD 로 만들기를 건너뛰고 규칙만 본다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

SCRIPT="$REPO/scripts/camp-media.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

chmod +x "$REPO/tests/mock/higgsfield" 2>/dev/null
export PATH="$REPO/tests/mock:$PATH"
export CAMP_MEDIA_FAKE_DOWNLOAD=1

TEAM="$TMP/03조_지구지킴이"
mkdir -p "$TEAM/assets"

# --- 1) 그림 ---
OUT="$(bash "$SCRIPT" --kind 그림 --prompt "clean ocean illustration" --team-dir "$TEAM" 2>/dev/null)"
assert_eq "$?" "0" "그림 생성이 성공"
assert_contains "$OUT" "assets/" "출력이 assets 상대경로"
assert_eq "$OUT" "assets/그림-1.png" "그림 이름에 번호가 붙음"

# --- 2) 횟수 제한 없음 (주최측 결정: 학생을 막지 않는다) ---
for i in 1 2 3 4 5 6 7 8; do
  bash "$SCRIPT" --kind 대표 --prompt "poster $i" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "대표 그림을 여러 번 만들어도 막지 않음"

# --- 3) 음악은 제한 없음 ---
for i in 1 2 3 4 5; do
  bash "$SCRIPT" --kind 음악 --prompt "gentle ocean bgm" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "음악은 5회째도 허용"

# --- 4) 영상도 횟수 제한 없음. 모델과 길이만 고정한다 ---
for i in 1 2 3; do
  bash "$SCRIPT" --kind 영상 --prompt "clip $i" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "영상 3회째도 막지 않음"

# --- 5) 카운터가 팀 폴더에 저장된다 ---
assert_file "$TEAM/.camp/counts" "카운터 파일 존재"
assert_contains "$(cat "$TEAM/.camp/counts")" "영상=3" "영상 기록이 3"

# --- 6) 카운터는 팀별로 독립 ---
TEAM2="$TMP/07조_별빛"
mkdir -p "$TEAM2/assets"
bash "$SCRIPT" --kind 영상 --prompt "other team clip" --team-dir "$TEAM2" >/dev/null 2>&1
assert_eq "$?" "0" "다른 팀은 영상 카운터가 따로임"

# --- 7) 인자 검증 ---
bash "$SCRIPT" --kind 그림 --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "4" "prompt 누락은 exit 4"
bash "$SCRIPT" --kind 이상한것 --prompt "x" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "4" "알 수 없는 kind 는 exit 4"
bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TMP/없는팀" >/dev/null 2>&1
assert_eq "$?" "4" "없는 팀 폴더는 exit 4"

# --- 8) 만들기 도구가 없으면 사람 말로 알린다 ---
# (제공자별 상세 검증은 test-media-providers.sh 가 가짜 서버로 한다)
TEAM3="$TMP/09조_실패시험"
mkdir -p "$TEAM3/assets"
ERR="$( unset CAMP_MEDIA_FAKE_DOWNLOAD
        PATH="/usr/bin:/bin"
        bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TEAM3" 2>&1 >/dev/null )"
RC8=$?
if [ "$RC8" -ne 0 ]; then pass "만들기 도구가 없으면 실패로 끝남"
else fail "도구가 없는데 성공함"; fi
assert_not_contains "$ERR" "Error" "학생에게 영어 오류를 보이지 않음"

# 크레딧이 바닥났을 때를 따로 구분한다 (당일 실제로 일어날 수 있다)
SRC8="$(cat "$SCRIPT")"
assert_contains "$SRC8" "재료가 다 떨어졌어요" "크레딧 소진을 따로 안내"
assert_contains "$SRC8" "exit 7" "크레딧 소진은 다른 종료코드"

# --- 9) 실패는 기록을 늘리지 않는다 (크레딧이 안 나갔으니까) ---
BEFORE="$(grep '^영상=' "$TEAM2/.camp/counts" 2>/dev/null | cut -d= -f2)"
( unset CAMP_MEDIA_FAKE_DOWNLOAD
  PATH="/usr/bin:/bin"
  bash "$SCRIPT" --kind 영상 --prompt "x" --team-dir "$TEAM2" >/dev/null 2>&1 )
AFTER="$(grep '^영상=' "$TEAM2/.camp/counts" 2>/dev/null | cut -d= -f2)"
assert_eq "$AFTER" "$BEFORE" "실패 시 영상 카운터가 늘지 않음"

# --- 10) 모델과 길이가 코드에 고정돼 있다 ---
SRC="$(cat "$SCRIPT")"
assert_contains "$SRC" 'MODEL="nano_banana_2_lite"' "그림은 nano_banana_2_lite (1크레딧)"
assert_contains "$SRC" 'MODEL="nano_banana_2"' "대표는 nano_banana_2 (한글이 된다)"
assert_contains "$SRC" 'MODEL="veo3_1_lite"' "영상은 veo3_1_lite (8크레딧)"
assert_not_contains "$SRC" "seedance_2_5" "가장 비싼 영상 모델은 쓰지 않음"
assert_contains "$SRC" "12m" "영상은 오래 기다려 준다"

summary
