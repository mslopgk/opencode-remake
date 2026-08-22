#!/usr/bin/env bash
# 치트시트에 적힌 명령어가 실제로 존재하는지 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

C="$REPO/docs/운영/학생용-치트시트.md"
assert_file "$C" "치트시트 존재"
assert_file "$REPO/docs/운영/사전온라인교육-2시간.md" "사전교육 커리큘럼 존재"
assert_file "$REPO/docs/운영/멘토용-트러블슈팅.md" "멘토용 문서 존재"
assert_file "$REPO/README.md" "README 존재"

# 치트시트가 언급한 모든 /명령어가 실제로 있어야 한다
for c in $(grep -oE '/[가-힣]+' "$C" 2>/dev/null | sort -u | tr -d '/'); do
  if [ -f "$REPO/camp-preset/command/$c.md" ]; then
    pass "치트시트 명령어 존재: /$c"
  else
    fail "치트시트에 있으나 구현 없음: /$c"
  fi
done

# 사전교육 문서가 실제 진입점 이름을 쓰는가
G="$(cat "$REPO/docs/운영/사전온라인교육-2시간.md" 2>/dev/null || echo '')"
assert_contains "$G" "설치하기" "사전교육 문서가 설치하기 진입점을 안내"
assert_contains "$G" "초록불" "사전교육 문서가 자체 점검을 안내"

# 멘토 문서가 점검하기·캠프시작을 안내하는가
T="$(cat "$REPO/docs/운영/멘토용-트러블슈팅.md" 2>/dev/null || echo '')"
assert_contains "$T" "점검하기" "멘토 문서가 재점검 방법을 안내"
assert_contains "$T" "캠프시작" "멘토 문서가 런처를 안내"

# README 가 배포판 빌드 절차를 담는가
R="$(cat "$REPO/README.md" 2>/dev/null || echo '')"
assert_contains "$R" "build-dist" "README 에 배포판 빌드 절차"
assert_contains "$R" "fetch-bundle" "README 에 번들 수집 절차"

summary
