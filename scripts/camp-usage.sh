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

# 어느 쪽에 돈이 나갔는지. 만든 곳은 네 번째 칸에 있다.
# (2026-09-05 부터 기록된다. 그 전 것은 빈칸으로 나온다)
PROV=$(find "$ROOT" -type f -path '*/.camp/usage.log' 2>/dev/null -exec cat {} + 2>/dev/null |
  awk -F'	' 'NF>=5 && $4!=""{c[$4]++} END{for (k in c) printf "%s %d개  ", k, c[k]}')


if [ "$FOUND" = "0" ]; then
  echo "아직 만든 것이 없어요."
  exit 0
fi

if [ -n "${PROV:-}" ]; then
  echo
  echo "만든 곳별: $PROV"
fi

printf -- '------------------------------------------------------------\n'
printf '%-22s %8s %8s %8s %10s\n' "합계" "" "" "" "$TOTAL"
echo
echo "영상만 돈이 크게 나갑니다 (한 편 약 \$0.20)."
echo "총액은 Google Cloud 결제 계정의 예산 알림으로 지켜보세요."
