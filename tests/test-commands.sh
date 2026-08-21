#!/usr/bin/env bash
# 명령어 파일 10종의 정적 검증.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

CMDS="시작 아이디어 포스터 음악 영상 슬라이드추가 보여줘 발표연습 제출 도와줘"
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
assert_contains "$V" "2번" "/영상 이 횟수 제한을 안내"

summary
