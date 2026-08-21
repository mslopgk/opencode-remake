#!/usr/bin/env bash
# 프리셋 파일들이 문법적으로 유효한지 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

# opencode.json 이 유효한 JSON 인가
assert_file "$REPO/camp-preset/opencode.json" "opencode.json 존재"
python -c "import json,io,sys; json.load(io.open(sys.argv[1],encoding='utf-8'))" \
  "$REPO/camp-preset/opencode.json" 2>/dev/null
assert_eq "$?" "0" "opencode.json 이 유효한 JSON"

assert_file "$REPO/camp-preset/tui.json" "tui.json 존재"
python -c "import json,io,sys; json.load(io.open(sys.argv[1],encoding='utf-8'))" \
  "$REPO/camp-preset/tui.json" 2>/dev/null
assert_eq "$?" "0" "tui.json 이 유효한 JSON"

# autoupdate 는 반드시 false (캠프 중 버전이 바뀌면 안 된다)
AU=$(python -c "import json,io,sys; print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('autoupdate'))" \
  "$REPO/camp-preset/opencode.json")
assert_eq "$AU" "False" "autoupdate 가 false"

# 기본 모델이 deepseek-v4-flash 인가
MODEL=$(python -c "import json,io,sys; print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('model'))" \
  "$REPO/camp-preset/opencode.json")
assert_eq "$MODEL" "deepseek/deepseek-v4-flash" "기본 모델이 deepseek-v4-flash"

# 금지 모델이 어디에도 등장하지 않는가
if grep -rq "deepseek-chat" "$REPO/camp-preset/" 2>/dev/null; then
  fail "금지 모델 deepseek-chat 이 프리셋에 등장"
else
  pass "금지 모델 deepseek-chat 미사용"
fi

# 모든 agent/command 마크다운이 frontmatter 로 시작하는가
for f in "$REPO"/camp-preset/agent/*.md "$REPO"/camp-preset/command/*.md; do
  [ -e "$f" ] || continue
  head -1 "$f" | grep -q '^---$'
  assert_eq "$?" "0" "frontmatter 시작: $(basename "$f")"
  grep -q '^description:' "$f"
  assert_eq "$?" "0" "description 존재: $(basename "$f")"
done

# 스킬 이름은 ASCII 소문자+하이픈만
for d in "$REPO"/camp-preset/skills/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    pass "스킬 이름 규격: $name"
  else
    fail "스킬 이름 규격 위반: $name"
  fi
done

# AGENTS.md 필수 항목
AG="$REPO/camp-preset/AGENTS.md"
assert_file "$AG" "AGENTS.md 존재"
BODY="$(cat "$AG" 2>/dev/null || echo '')"
assert_contains "$BODY" "디자인씽킹" "AGENTS.md 에 캠프 주제"
assert_contains "$BODY" "AI·디지털" "AGENTS.md 에 트랙1"
assert_contains "$BODY" "지구·환경" "AGENTS.md 에 트랙2"
assert_contains "$BODY" "한 번에 한 가지만" "AGENTS.md 에 질문 규칙"
assert_contains "$BODY" "이름을 묻지 않습니다" "AGENTS.md 에 개인정보 규칙"
assert_contains "$BODY" "우리팀.md" "AGENTS.md 에 팀 기록 파일 규칙"
assert_contains "$BODY" "9월 19일" "AGENTS.md 에 캠프 일정"
# AGENTS.md 는 지시문이므로 금지 용어를 "목록으로" 담아야 한다.
# (학생 대면 텍스트가 아니므로 금지어가 등장하는 것이 정상)
assert_contains "$BODY" "전문용어를 쓰지 않습니다" "AGENTS.md 에 금지 용어 규칙"
assert_contains "$BODY" "터미널, 커맨드" "AGENTS.md 에 금지 용어 목록"

summary
