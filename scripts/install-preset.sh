#!/usr/bin/env bash
# 캠프 프리셋을 opencode 설정 디렉토리에 설치한다.
# 사용법: install-preset.sh [--target <디렉토리>] [--force]
# exit 6 = 대상이 이미 있고 --force 가 없음
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${HOME}/.config/opencode"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 4 ;;
  esac
done

if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "이미 설정이 있습니다: $TARGET" >&2
    echo "덮어쓰려면 --force 를 쓰세요. 기존 설정은 백업됩니다." >&2
    exit 6
  fi
  TS="$(date +%Y%m%d-%H%M%S)"
  BK="${TARGET}.backup-${TS}"
  mv "$TARGET" "$BK"
  echo "기존 설정을 백업했습니다: $BK"
fi

mkdir -p "$TARGET"
cp -r "$REPO/camp-preset/." "$TARGET/"
echo "설치 완료: $TARGET"
