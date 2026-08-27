#!/usr/bin/env bash
# 스킬 파일의 frontmatter 와 필수 내용을 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

for s in media-generation web-slides campaign-planning presentation-script; do
  F="$REPO/camp-preset/skills/$s/SKILL.md"
  assert_file "$F" "스킬 파일 존재: $s"
  [ -f "$F" ] || continue
  head -1 "$F" | grep -q '^---$'
  assert_eq "$?" "0" "frontmatter 시작: $s"
  NAME="$(grep -m1 '^name:' "$F" | sed 's/^name:[[:space:]]*//')"
  assert_eq "$NAME" "$s" "name 이 디렉토리명과 일치: $s"
  grep -q '^description:' "$F"
  assert_eq "$?" "0" "description 존재: $s"
done

# web-slides 는 템플릿 구조를 정확히 참조해야 한다
W="$(cat "$REPO/camp-preset/skills/web-slides/SKILL.md" 2>/dev/null || echo '')"
assert_contains "$W" 'class="slide"' "web-slides 가 slide 클래스를 명시"
assert_contains "$W" "data-theme" "web-slides 가 테마 전환 방법을 명시"
assert_contains "$W" "ocean" "web-slides 가 테마 이름을 명시"
# 스킬은 지시문이므로 빌드 도구를 "금지 조항으로" 담아야 한다
assert_contains "$W" "빌드 도구는 쓰지 않는다" "web-slides 가 빌드 도구를 금지"
assert_contains "$W" "CDN 은 써도 된다" "web-slides 가 CDN 을 허용"

# campaign-planning 은 HMW 절차를 담아야 한다
C="$(cat "$REPO/camp-preset/skills/campaign-planning/SKILL.md" 2>/dev/null || echo '')"
assert_contains "$C" "How Might We" "campaign-planning 에 HMW"
assert_contains "$C" "우리팀.md" "campaign-planning 이 기록 파일을 명시"

assert_contains "$W" "slides/" "web-slides 가 분리 구조를 설명"
assert_contains "$W" "자기 파일만" "web-slides 가 자기 파일만 고치라고 지시"

summary
