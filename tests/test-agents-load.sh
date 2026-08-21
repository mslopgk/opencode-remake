#!/usr/bin/env bash
# opencode 가 캠프 에이전트를 실제로 로드하는지 검증한다.
# 개발자의 실제 설정을 건드리지 않기 위해 OPENCODE_CONFIG_DIR 로 격리한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if ! command -v opencode >/dev/null 2>&1; then
  fail "opencode 가 PATH 에 없음"
  summary; exit 1
fi

# Windows 경로로 변환 (Git Bash 경로를 opencode 가 못 읽는 경우 대비)
CFG="$REPO/camp-preset"
if command -v cygpath >/dev/null 2>&1; then CFG="$(cygpath -m "$CFG")"; fi

LIST="$(OPENCODE_CONFIG_DIR="$CFG" opencode agent list 2>&1)"

assert_contains "$LIST" "도우미 (primary)" "도우미 가 primary 로 로드됨"
assert_contains "$LIST" "아이디어 (subagent)" "아이디어 가 subagent 로 로드됨"
assert_contains "$LIST" "디자이너 (subagent)" "디자이너 가 subagent 로 로드됨"
assert_contains "$LIST" "미디어 (subagent)" "미디어 가 subagent 로 로드됨"

summary
