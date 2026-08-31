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

# --- 8) 열쇠가 없으면 만들지 않고 사람 말로 알린다 ---
# (실제 실패 경로는 test-media-providers.sh 가 가짜 서버로 더 자세히 본다)
TEAM3="$TMP/09조_실패시험"
mkdir -p "$TEAM3/assets"
ERR="$( unset CAMP_MEDIA_FAKE_DOWNLOAD
        export CAMP_MEDIA_KEYS="$TMP/없는열쇠.env"
        unset CF_ACCOUNT_ID CF_API_TOKEN
        bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TEAM3" 2>&1 >/dev/null )"
assert_eq "$?" "6" "열쇠가 없으면 exit 6"
assert_contains "$ERR" "열쇠가 없어요" "실패 메시지가 한국어"

# --- 9) 실패는 기록을 늘리지 않는다 (돈이 안 나갔으니까) ---
BEFORE="$(grep '^영상=' "$TEAM2/.camp/counts" 2>/dev/null | cut -d= -f2)"
( unset CAMP_MEDIA_FAKE_DOWNLOAD
  export CAMP_MEDIA_KEYS="$TMP/없는열쇠.env"
  unset FAL_KEY
  bash "$SCRIPT" --kind 영상 --prompt "x" --team-dir "$TEAM2" >/dev/null 2>&1 )
AFTER="$(grep '^영상=' "$TEAM2/.camp/counts" 2>/dev/null | cut -d= -f2)"
assert_eq "$AFTER" "$BEFORE" "실패 시 영상 카운터가 늘지 않음"

summary
