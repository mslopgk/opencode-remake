#!/usr/bin/env bash
# 설치 스크립트가 기존 설정을 덮어쓰지 않는지 검증한다.
# 개발자의 실제 ~/.config/opencode 는 절대 건드리지 않는다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"
S="$REPO/scripts/install-preset.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1) 빈 대상에 설치
T1="$TMP/cfg1"
bash "$S" --target "$T1" >/dev/null 2>&1
assert_eq "$?" "0" "빈 대상에 설치 성공"
assert_file "$T1/AGENTS.md" "AGENTS.md 설치됨"
assert_file "$T1/opencode.json" "opencode.json 설치됨"
assert_file "$T1/agent/도우미.md" "에이전트 설치됨"
assert_file "$T1/command/시작.md" "명령어 설치됨"
assert_file "$T1/skills/web-slides/SKILL.md" "스킬 설치됨"

# 2) 이미 있는 대상은 --force 없이 거부
bash "$S" --target "$T1" >/dev/null 2>&1
assert_eq "$?" "6" "기존 대상은 --force 없이 거부 (exit 6)"

# 3) --force 는 백업을 만든 뒤 설치
echo "내 원래 설정" > "$T1/내파일.txt"
bash "$S" --target "$T1" --force >/dev/null 2>&1
assert_eq "$?" "0" "--force 로 재설치 성공"
BK="$(ls -d "$T1".backup-* 2>/dev/null | head -1)"
if [ -n "$BK" ]; then pass "백업 디렉토리 생성"; else fail "백업이 만들어지지 않음"; fi
assert_file "$BK/내파일.txt" "기존 파일이 백업에 보존됨"

summary
