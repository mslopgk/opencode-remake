#!/bin/bash
# 맥에서 캠프가 넣은 것을 지운다.
#
# 왜 필요한가:
#   설치가 반쯤 되다 만 맥을 되살리려면 깨끗이 지우고 다시 까는 편이 빠르다.
#   그리고 캠프가 끝나면 학생 노트북에서 우리 것을 걷어내야 한다
#   (특히 열쇠는 반드시 지워야 한다).
#
# 무엇을 지우는가:
#   캠프 앱, 도구, 캠프 설정, 열쇠, 바탕화면 아이콘, 잘못 만들어진 폴더
#
# 무엇을 절대 안 지우는가:
#   학생이 만든 작품 (~/창의디자인캠프/연습, 내캠페인, 바탕화면 작업 폴더)
#   파이썬, Git, 다른 앱 — 학생이 원래 쓰던 것일 수 있다
#
# 쓰는 법:
#   bash ~/.local/bin/mac-uninstall.sh          (물어보고 지운다)
#   bash ~/.local/bin/mac-uninstall.sh --예     (안 물어보고 지운다)

set -u

BIN="$HOME/.local/bin"
CAMPDIR="$HOME/창의디자인캠프"
NOASK=0
[ "${1:-}" = "--예" ] && NOASK=1
[ "${1:-}" = "-y" ] && NOASK=1

echo
echo "=============================================="
echo "   창의디자인캠프 지우기 (맥)"
echo "=============================================="
echo

# 지울 것을 먼저 모은다. 보여주고 나서 지운다.
TARGETS=()
LABELS=()

add_target() {   # 담기 <경로> <설명>
  if [ -e "$1" ] || [ -L "$1" ]; then
    TARGETS+=("$1")
    LABELS+=("$2")
  fi
}

# 앱
for PLACE in "$HOME/Applications" "/Applications"; do
  while IFS= read -r APPFOUND; do
    [ -n "$APPFOUND" ] && add_target "$APPFOUND" "캠프 앱"
  done <<EOF
$(find "$PLACE" -maxdepth 1 -name 'OpenCode*.app' 2>/dev/null)
EOF
done

# 도구
for t in camp-media.sh merge-slides.sh merge-slides.py camp-publish.sh \
         media-gen.py camp-usage.sh new-team.sh opencode gh \
         mac-check.sh mac-uninstall.sh mac-fix.sh; do
  add_target "$BIN/$t" "도구 $t"
done

# 설정과 열쇠
add_target "$HOME/.config/opencode"            "캠프 설정"
add_target "$HOME/.config/camp"                "그림 열쇠"
add_target "$HOME/.local/share/opencode"       "AI 열쇠와 대화 기록"
add_target "$HOME/.cache/opencode"             "앱이 받아 둔 것"
add_target "$HOME/.local/Programs/camp-tools"  "도구 이어주는 길"

# 바탕화면 아이콘 (작업 폴더는 건드리지 않는다)
add_target "$HOME/Desktop/캠프 시작"           "바탕화면 아이콘"
add_target "$HOME/Desktop/캠프 시작.app"       "바탕화면 아이콘"
add_target "$HOME/Desktop/점검.command"        "바탕화면 아이콘"
add_target "$HOME/Desktop/캠프 지우기.command" "바탕화면 아이콘"
add_target "$HOME/Desktop/도구 고치기.command" "바탕화면 아이콘"

# 줄바꿈 사고로 생긴 유령 폴더 (이름 끝에 보이지 않는 글자가 있다)
while IFS= read -r GHOST; do
  [ -n "$GHOST" ] && add_target "$GHOST" "잘못 만들어진 폴더"
done <<EOF
$(find "$HOME" -maxdepth 3 -name '*'$'\r' 2>/dev/null)
EOF

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "지울 것이 없어요. 이 맥에는 캠프가 안 깔려 있습니다."
  exit 0
fi

echo "이런 것들을 지웁니다:"
echo
i=0
while [ "$i" -lt "${#TARGETS[@]}" ]; do
  SIZE=$(du -sh "${TARGETS[$i]}" 2>/dev/null | cut -f1)
  printf '  %-12s %s  (%s)\n' "${LABELS[$i]}" "${TARGETS[$i]}" "${SIZE:-?}" | cat -v
  i=$((i+1))
done

echo
echo "학생이 만든 작품은 지우지 않습니다:"
echo "  $CAMPDIR/연습"
echo "  바탕화면의 내캠페인 같은 작업 폴더"
echo

if [ "$NOASK" != "1" ]; then
  printf '정말 지울까요? 지우려면  네  라고 치고 엔터: '
  read -r REPLY < /dev/tty
  case "$REPLY" in
    네|ㅇㅇ|y|Y|yes|YES) ;;
    *) echo "그만뒀어요. 아무것도 안 지웠습니다."; exit 0 ;;
  esac
fi

echo
REMOVED=0
for P in "${TARGETS[@]}"; do
  # 안전장치: 홈 폴더 안의 것만 지운다. /Applications 는 예외로 허용한다.
  case "$P" in
    "$HOME"/*|/Applications/OpenCode*.app) ;;
    *) echo "  건너뜀 (홈 밖이라 안 건드립니다): $P"; continue ;;
  esac
  # 안전장치: 작품 폴더는 절대 안 지운다.
  case "$P" in
    "$CAMPDIR"|"$CAMPDIR"/연습*|"$HOME/Desktop/내캠페인"*)
      echo "  건너뜀 (학생 작품): $P"; continue ;;
  esac
  if rm -rf "$P" 2>/dev/null; then
    REMOVED=$((REMOVED+1))
  else
    echo "  못 지웠어요: $P" | cat -v
  fi
done

# PATH 에 넣어 둔 줄도 걷어낸다
for RC in "$HOME/.zshrc" "$HOME/.bash_profile"; do
  [ -f "$RC" ] || continue
  if grep -q 'camp: .local/bin' "$RC" 2>/dev/null; then
    TMPF=$(mktemp) || continue
    grep -v -e 'camp: .local/bin' -e 'export PATH="$HOME/.local/bin:$PATH"' "$RC" > "$TMPF" 2>/dev/null \
      && cat "$TMPF" > "$RC"
    rm -f "$TMPF"
  fi
done

echo
echo "$REMOVED 개를 지웠어요."
echo "다시 깔려면 설치를 한 번 더 하면 됩니다."
