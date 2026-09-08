#!/usr/bin/env bash
# 친구들이 각자 만든 slides/*.html 을 index.html 하나로 합친다.
#
# 왜 스크립트인가: 합치기는 결정적인 텍스트 작업이다. LLM 에게 맡기면
# 느리고(실측 10분 초과) 결과가 들쭉날쭉하다. camp-media.sh 가 크레딧을
# 강제하는 것과 같은 이유로, 기계적인 일은 기계가 한다.
#
# 왜 python 을 별도 파일로 부르는가: 여기서 `python - <<'PY'` 로 넘기면
# opencode 의 bash 툴에서 python 이 stdin 을 기다리며 멈춘다(실측).
# 에이전트가 실행하는 스크립트는 stdin 을 읽으면 안 된다.
#
# 사용법: merge-slides.sh --team-dir <팀폴더>
# 성공: 합친 장 수를 stdout 한 줄로 출력 (예: "3")
# exit 4=인자 오류, 5=조립 지점 없음
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --team-dir) [ $# -ge 2 ] || { echo "값이 빠졌어요." >&2; exit 4; }; TEAM_DIR="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션이에요: $1" >&2; exit 4 ;;
  esac
done

[ -n "$TEAM_DIR" ] || { echo "팀 폴더가 필요해요." >&2; exit 4; }

# 윈도우에는 실행하면 "스토어에서 설치하라" 고만 하는 가짜 python 이 있다(실측).
# 이름만 보지 말고 실제로 되는지 확인한다. camp-media.sh 와 같은 방식이다.
PY=""
for c in python py python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then
    PY="$c"; break
  fi
done
if [ -z "$PY" ]; then
  echo "합치는 도구가 없어요. 선생님을 불러 주세요." >&2
  exit 5
fi

# 파이썬이 한국어 메시지를 cp949 로 쓰면 학생 화면에서 깨진다(이 프로젝트가
# 반복해서 겪은 사고). 여기서도 못박는다.
export PYTHONIOENCODING=utf-8
exec "$PY" "$HERE/merge-slides.py" "$TEAM_DIR" < /dev/null
