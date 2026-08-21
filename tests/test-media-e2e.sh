#!/usr/bin/env bash
# 실제 higgsfield 를 호출하는 E2E. 1크레딧을 쓴다.
# CAMP_E2E=1 일 때만 실행한다 (기본은 건너뛴다).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if [ "${CAMP_E2E:-0}" != "1" ]; then
  echo "  skip 실제 크레딧을 쓰는 테스트 (CAMP_E2E=1 로 실행)"
  summary; exit 0
fi

assert_file "$REPO/camp-preset/skills/media-generation/SKILL.md" "media-generation 스킬 존재"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TEAM="$TMP/99조_테스트"
mkdir -p "$TEAM/assets"

REL="$(bash "$REPO/scripts/camp-media.sh" --kind 그림 \
        --prompt "simple flat illustration of a clean blue ocean, children book style" \
        --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "실제 그림 생성 성공"
assert_contains "$REL" "assets/" "상대경로 반환"
assert_file "$TEAM/$REL" "파일이 실제로 저장됨"

SIZE=$(wc -c < "$TEAM/$REL" 2>/dev/null || echo 0)
if [ "$SIZE" -gt 10000 ]; then pass "파일 크기가 10KB 초과 ($SIZE bytes)"
else fail "파일이 너무 작음 ($SIZE bytes) — 다운로드 실패 의심"; fi

summary
