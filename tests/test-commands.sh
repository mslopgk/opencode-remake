#!/usr/bin/env bash
# 명령어 파일 10종의 정적 검증.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

CMDS="시작 아이디어 포스터 음악 영상 슬라이드추가 보여줘 발표연습 제출 도와줘 합쳐줘"
VALID_AGENTS="도우미 아이디어 디자이너 미디어"

for c in $CMDS; do
  F="$REPO/camp-preset/command/$c.md"
  assert_file "$F" "명령어 존재: /$c"
  [ -f "$F" ] || continue
  grep -q '^description:' "$F"
  assert_eq "$?" "0" "description 존재: /$c"
  A="$(grep -m1 '^agent:' "$F" | sed 's/^agent:[[:space:]]*//')"
  if [ -n "$A" ]; then
    case " $VALID_AGENTS " in
      *" $A "*) pass "agent 유효: /$c → $A" ;;
      *) fail "agent 가 존재하지 않음: /$c → $A" ;;
    esac
  fi
  # frontmatter(--- 로 감싼 두 줄) 이후의 본문만 뽑는다
  BODY="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
  assert_not_contains "$BODY" "터미널" "금지 용어 없음(터미널): /$c"
done

# /보여줘 는 브라우저를 여는 방법을 명시해야 한다
S="$(cat "$REPO/camp-preset/command/보여줘.md" 2>/dev/null || echo '')"
assert_contains "$S" "start" "/보여줘 가 브라우저 여는 명령을 포함"

# /포스터 는 camp-media.sh 를 쓰도록 지시해야 한다
P="$(cat "$REPO/camp-preset/command/포스터.md" 2>/dev/null || echo '')"
assert_contains "$P" "camp-media.sh" "/포스터 가 래퍼를 사용"
assert_not_contains "$P" "higgsfield generate" "/포스터 가 CLI 를 직접 쓰지 않음"

# /영상 은 횟수 제한을 학생에게 알려야 한다
V="$(cat "$REPO/camp-preset/command/영상.md" 2>/dev/null || echo '')"
# 횟수는 제한하지 않기로 했다. 대신 길이가 고정이라는 것을 알려야 한다.
assert_contains "$V" "5초" "/영상 이 정해진 길이를 안내"
assert_not_contains "$V" "2번까지" "/영상 이 없는 제한을 말하지 않음"

# /합쳐줘 는 slides 조립을 지시해야 한다
M="$(cat "$REPO/camp-preset/command/합쳐줘.md" 2>/dev/null || echo '')"
assert_contains "$M" "slides/" "/합쳐줘 가 slides 폴더를 참조"
assert_contains "$M" "merge-slides.sh" "/합쳐줘 가 스크립트를 사용"
assert_contains "$M" "camp-tools" "/합쳐줘 가 절대경로를 사용(PATH 의존 금지)"
# 셸 주입으로 결정적으로 실행되어야 한다. LLM 판단에 맡기면 안 된다
if grep -qF '!`' "$REPO/camp-preset/command/합쳐줘.md"; then
  pass "/합쳐줘 가 셸 주입으로 실행"
else
  fail "/합쳐줘 가 셸 주입을 쓰지 않음"
fi
assert_not_contains "$M" "주석 바로 아래에 넣어라" "/합쳐줘 가 직접 편집을 지시하지 않음"

# 도구를 쓰는 명령어·스킬은 PATH 에 의존하면 안 된다
# (실측: opencode 의 bash 가 보는 PATH 에 도구가 없어 에이전트가 디스크를 헤맸다)
for f in "$REPO"/camp-preset/command/포스터.md "$REPO"/camp-preset/command/음악.md          "$REPO"/camp-preset/command/영상.md "$REPO"/camp-preset/skills/media-generation/SKILL.md; do
  [ -e "$f" ] || continue
  BODY2="$(cat "$f")"
  assert_contains "$BODY2" "camp-tools" "절대경로 사용: $(basename "$f")"
done

summary
