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

summary
