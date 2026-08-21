#!/usr/bin/env bash
# camp-media.sh 단위 테스트. mock higgsfield 를 써서 크레딧을 쓰지 않는다.
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

# --- 1) 기본 그림은 저가 모델을 쓴다 ---
export MOCK_LOG="$TMP/log1"
: > "$MOCK_LOG"
OUT="$(bash "$SCRIPT" --kind 그림 --prompt "clean ocean illustration" --team-dir "$TEAM" 2>/dev/null)"
assert_eq "$?" "0" "그림 생성이 성공"
assert_contains "$OUT" "assets/" "출력이 assets 상대경로"
assert_contains "$(cat "$MOCK_LOG")" "nano_banana_2_lite" "기본 그림은 nano_banana_2_lite(1크레딧)"
assert_not_contains "$(cat "$MOCK_LOG")" "gpt_image_2" "기본 그림에 고가 모델을 쓰지 않음"

# --- 2) 대표 이미지는 gpt_image_2, 팀당 2회 제한 ---
export MOCK_LOG="$TMP/log2"
: > "$MOCK_LOG"
bash "$SCRIPT" --kind 대표 --prompt "campaign poster" --team-dir "$TEAM" >/dev/null 2>&1
assert_contains "$(cat "$MOCK_LOG")" "gpt_image_2" "대표 이미지는 gpt_image_2"
bash "$SCRIPT" --kind 대표 --prompt "poster 2" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "대표 이미지 2회째는 허용"
bash "$SCRIPT" --kind 대표 --prompt "poster 3" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "3" "대표 이미지 3회째는 거부 (exit 3)"

# --- 3) 음악은 seed_audio, 제한 없음 ---
export MOCK_LOG="$TMP/log3"
: > "$MOCK_LOG"
for i in 1 2 3 4 5; do
  bash "$SCRIPT" --kind 음악 --prompt "gentle ocean bgm" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "음악은 5회째도 허용"
assert_contains "$(cat "$MOCK_LOG")" "seed_audio" "음악은 seed_audio(0.1크레딧)"

# --- 4) 영상은 seedance_2_0, 팀당 2회 제한 ---
export MOCK_LOG="$TMP/log4"
: > "$MOCK_LOG"
bash "$SCRIPT" --kind 영상 --prompt "ocean cleanup clip" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "영상 1회째 허용"
assert_contains "$(cat "$MOCK_LOG")" "seedance_2_0" "영상은 seedance_2_0"
bash "$SCRIPT" --kind 영상 --prompt "clip 2" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "영상 2회째 허용"
bash "$SCRIPT" --kind 영상 --prompt "clip 3" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "2" "영상 3회째는 거부 (exit 2)"

# --- 5) 카운터가 팀 폴더에 저장된다 ---
assert_file "$TEAM/.camp/counts" "카운터 파일 존재"
assert_contains "$(cat "$TEAM/.camp/counts")" "영상=2" "영상 카운터가 2"

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

# --- 8) 생성 실패는 exit 5 와 한국어 메시지 ---
export MOCK_FAIL=1
ERR="$(bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TEAM" 2>&1 >/dev/null)"
assert_eq "$?" "5" "생성 실패는 exit 5"
assert_contains "$ERR" "만들지 못했어요" "실패 메시지가 한국어"
unset MOCK_FAIL

# --- 9) 실패는 카운터를 늘리지 않는다 ---
BEFORE="$(grep '^영상=' "$TEAM2/.camp/counts" | cut -d= -f2)"
export MOCK_FAIL=1
bash "$SCRIPT" --kind 영상 --prompt "x" --team-dir "$TEAM2" >/dev/null 2>&1
unset MOCK_FAIL
AFTER="$(grep '^영상=' "$TEAM2/.camp/counts" | cut -d= -f2)"
assert_eq "$AFTER" "$BEFORE" "실패 시 영상 카운터가 늘지 않음"

summary
