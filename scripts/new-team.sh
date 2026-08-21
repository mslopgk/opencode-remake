#!/usr/bin/env bash
# 팀 폴더를 만들고 발표자료 템플릿을 넣는다.
# 사용법: new-team.sh <조번호 1-15> <팀이름> [부모디렉토리]
# 성공: 만든 폴더의 절대경로를 stdout 출력. exit 4=인자오류, 5=이미존재
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NUM="${1:-}"; NAME="${2:-}"; PARENT="${3:-$PWD}"

[ -n "$NUM" ] && [ -n "$NAME" ] || { echo "조 번호와 팀 이름이 필요해요." >&2; exit 4; }
case "$NUM" in ''|*[!0-9]*) echo "조 번호는 숫자여야 해요." >&2; exit 4 ;; esac
if [ "$NUM" -lt 1 ] || [ "$NUM" -gt 15 ]; then
  echo "조 번호는 1부터 15까지예요." >&2; exit 4
fi
case "$NAME" in *[/\\:*?\"\<\>\|]*) echo "팀 이름에 쓸 수 없는 글자가 있어요." >&2; exit 4 ;; esac

PAD="$(printf '%02d' "$NUM")"
DIR="$PARENT/${PAD}조_${NAME}"

[ -e "$DIR" ] && { echo "이미 있는 팀 폴더예요: ${PAD}조_${NAME}" >&2; exit 5; }

mkdir -p "$DIR"
cp -r "$REPO/template/." "$DIR/"
mkdir -p "$DIR/assets"

# 조번호·팀이름 채우기
python - "$DIR" "$PAD" "$NAME" <<'PY'
import io, sys, os
d, pad, name = sys.argv[1], sys.argv[2], sys.argv[3]

p = os.path.join(d, "우리팀.md")
s = io.open(p, encoding="utf-8").read()
s = s.replace("- 조 번호: (아직 안 정함)", "- 조 번호: %s조" % pad)
s = s.replace("- 팀 이름: (아직 안 정함)", "- 팀 이름: %s" % name)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)

p = os.path.join(d, "index.html")
s = io.open(p, encoding="utf-8").read()
s = s.replace("00조 팀이름", "%s조 %s" % (pad, name))
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
PY

printf '%s\n' "$DIR"
