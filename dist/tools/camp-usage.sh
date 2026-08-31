#!/usr/bin/env bash
# 얼마나 썼는지 합계를 보여 준다 (운영진용).
#
# 횟수 제한을 없앴으므로 대신 이걸로 본다.
# 학생을 막지 않으면서 총액을 아는 것이 목적이다.
#
# 사용법:
#   camp-usage.sh [캠프폴더]      기본값: ~/창의디자인캠프
set -uo pipefail

ROOT="${1:-$HOME/창의디자인캠프}"
[ -d "$ROOT" ] || { echo "캠프 폴더를 찾을 수 없어요: $ROOT" >&2; exit 4; }

TOTAL=0
FOUND=0

printf '%-22s %8s %8s %8s %10s\n' "팀" "그림" "대표" "영상" "돈($)"
printf -- '------------------------------------------------------------\n'

while IFS= read -r log; do
  dir="$(dirname "$(dirname "$log")")"
  team="$(basename "$dir")"
  FOUND=1

  # bash 변수 이름에는 한글을 쓸 수 없다 (실행해 보고 알았다)
  n_img=$(awk -F'	' '$2=="그림"{n++} END{print n+0}' "$log")
  n_key=$(awk -F'	' '$2=="대표"{n++} END{print n+0}' "$log")
  n_vid=$(awk -F'	' '$2=="영상"{n++} END{print n+0}' "$log")
  money=$(awk -F'	' '{s+=$3} END{printf "%.2f", s+0}' "$log")

  printf '%-22s %8s %8s %8s %10s
' "$team" "$n_img" "$n_key" "$n_vid" "$money"
  TOTAL=$(awk -v a="$TOTAL" -v b="$money" 'BEGIN{printf "%.2f", a+b}')
done < <(find "$ROOT" -type f -path '*/.camp/usage.log' 2>/dev/null | sort)

if [ "$FOUND" = "0" ]; then
  echo "아직 만든 것이 없어요."
  exit 0
fi

printf -- '------------------------------------------------------------\n'
printf '%-22s %8s %8s %8s %10s\n' "합계" "" "" "" "$TOTAL"
echo
echo "영상만 돈이 크게 나갑니다 (한 편 약 \$0.40)."
echo "총액 한도는 fal.ai 대시보드의 spending cap 으로 거는 것이 안전합니다."
