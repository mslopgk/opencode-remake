#!/usr/bin/env bash
# 모든 테스트를 실행한다. 하나라도 실패하면 exit 1.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
for t in "$REPO"/tests/test-*.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then printf '\n전체 통과\n'; else printf '\n실패 있음\n' >&2; fi
exit "$rc"
