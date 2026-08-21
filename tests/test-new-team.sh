#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"
S="$REPO/scripts/new-team.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

DIR="$(bash "$S" 3 지구지킴이 "$TMP" 2>/dev/null)"
assert_eq "$?" "0" "팀 폴더 생성 성공"
assert_contains "$DIR" "03조_지구지킴이" "조번호가 두 자리로 정규화됨"
assert_file "$DIR/index.html" "index.html 복사됨"
assert_file "$DIR/우리팀.md" "우리팀.md 복사됨"
if [ -d "$DIR/assets" ]; then pass "assets 폴더 생성"; else fail "assets 폴더 없음"; fi

TEAMDOC="$(cat "$DIR/우리팀.md")"
assert_contains "$TEAMDOC" "조 번호: 03조" "우리팀.md 에 조번호 기입"
assert_contains "$TEAMDOC" "팀 이름: 지구지킴이" "우리팀.md 에 팀이름 기입"
assert_not_contains "$TEAMDOC" "팀 이름: (아직 안 정함)" "팀 이름 자리표시자가 남지 않음"
assert_not_contains "$TEAMDOC" "조 번호: (아직 안 정함)" "조 번호 자리표시자가 남지 않음"

HTML="$(cat "$DIR/index.html")"
assert_contains "$HTML" "03조 지구지킴이" "표지에 조번호·팀이름 반영"
assert_not_contains "$HTML" "00조 팀이름" "표지 자리표시자가 남지 않음"

bash "$S" 3 지구지킴이 "$TMP" >/dev/null 2>&1
assert_eq "$?" "5" "이미 있는 팀은 exit 5"

bash "$S" >/dev/null 2>&1
assert_eq "$?" "4" "인자 없으면 exit 4"
bash "$S" 0 팀 "$TMP" >/dev/null 2>&1
assert_eq "$?" "4" "조번호 0 은 exit 4"
bash "$S" 16 팀 "$TMP" >/dev/null 2>&1
assert_eq "$?" "4" "조번호 16 은 exit 4 (15개 조)"

summary
