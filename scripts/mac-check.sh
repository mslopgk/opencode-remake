#!/bin/bash
# 맥에서 캠프가 제대로 깔렸는지 본다. 윈도우의 "점검" 과 같은 일을 한다.
#
# 왜 필요한가 (실측, 2026-09-05 현장):
#   맥 한 대에서 "설치는 됐는데 대화가 안 된다" 가 나왔다. 그런데 맥에는
#   점검이 없어서, 무엇이 빠졌는지 알아낼 방법이 하나도 없었다.
#
#   특히 잘 나는 사고: 줄바꿈(CRLF) 때문에 열쇠가 `opencode` 가 아니라
#   `opencode<CR>` 폴더로 들어간다. 눈으로는 똑같아 보인다.
#   그래서 이 점검은 "폴더 이름 끝에 보이지 않는 글자가 있는지" 까지 본다.
#
# 쓰는 법:
#   bash ~/.local/bin/mac-check.sh
#   (바탕화면의 "점검" 을 두 번 눌러도 된다)

set -u

BIN="$HOME/.local/bin"
CFG="$HOME/.config/opencode"
CAMPDIR="$HOME/창의디자인캠프"
LOG="$CAMPDIR/점검기록.txt"

FAIL=0
mkdir -p "$CAMPDIR" 2>/dev/null

say()  {
  printf '%s\n' "$*"
  { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "${LOG:-/dev/null}"; } 2>/dev/null
  return 0
}
step() { say "[진행] $*"; }
ok()   { say "[완료] $*"; }
note() { say "[안내] $*"; }
bad()  { say "[실패] $*"; FAIL=$((FAIL+1)); }

: > "$LOG" 2>/dev/null

echo
echo "=============================================="
echo "   창의디자인캠프 점검 (맥)"
echo "=============================================="
echo

# ---------- 0. 보이지 않는 글자가 붙은 폴더 ----------
#
# 이게 있으면 나머지 점검이 전부 엉뚱한 곳을 보게 된다. 그래서 맨 먼저 본다.
GHOST=$(find "$HOME" -maxdepth 3 -name '*'$'\r' 2>/dev/null | head -5)
if [ -n "$GHOST" ]; then
  bad "이름이 이상한 폴더가 있어요. 예전에 설치가 잘못된 흔적이에요."
  printf '%s\n' "$GHOST" | while IFS= read -r LINE; do note "  $LINE" | cat -v; done
  note "지우려면 터미널에 이렇게 치세요:"
  note "  find ~ -maxdepth 3 -name '*'\$'\\r' -exec rm -rf {} + 2>/dev/null"
  note "그 다음 설치를 다시 하면 됩니다."
  echo
fi

# ---------- 1. 캠프 앱 ----------
step "1/7 캠프 앱이 있는지 확인 중"
APP=""
for PLACE in "$HOME/Applications" "/Applications"; do
  CAND=$(find "$PLACE" -maxdepth 1 -name 'OpenCode*.app' -print -quit 2>/dev/null)
  if [ -n "$CAND" ]; then APP="$CAND"; break; fi
done
if [ -n "$APP" ]; then
  ok "캠프 앱이 있어요  ($APP)"
else
  bad "캠프 앱이 없어요"
fi

# ---------- 2. 캠프 설정 ----------
step "2/7 캠프 설정이 들어갔는지 확인 중"
AG=$(ls -1 "$CFG/agent" 2>/dev/null | wc -l | tr -d ' ')
CM=$(ls -1 "$CFG/command" 2>/dev/null | wc -l | tr -d ' ')
SK=$(ls -1 "$CFG/skills" 2>/dev/null | wc -l | tr -d ' ')
if [ "${AG:-0}" -ge 4 ] && [ "${CM:-0}" -ge 11 ]; then
  ok "캠프 설정이 들어갔어요 (도우미 $AG, 명령 $CM, 재주 $SK)"
else
  bad "캠프 설정이 덜 들어갔어요 (도우미 ${AG:-0}/4, 명령 ${CM:-0}/11)"
  note "설치를 다시 하면 들어갑니다."
fi

# ---------- 3. 만들기 도구 ----------
step "3/7 만들기 도구가 있는지 확인 중"
MISSING=""
for t in camp-media.sh merge-slides.sh merge-slides.py camp-publish.sh media-gen.py camp-usage.sh; do
  [ -f "$BIN/$t" ] || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
  bad "만들기 도구가 없어요 ($MISSING)"
else
  # 윈도우 줄바꿈이 섞이면 맥에서 통째로 죽는다. 파일이 있는 것만으로는 부족하다.
  BROKEN=""
  for t in camp-media.sh merge-slides.sh camp-publish.sh; do
    if LC_ALL=C grep -q $'\r' "$BIN/$t" 2>/dev/null; then BROKEN="$BROKEN $t"; fi
  done
  if [ -n "$BROKEN" ]; then
    bad "만들기 도구가 윈도우 줄바꿈이라 맥에서 안 돌아요 ($BROKEN)"
    note "설치를 다시 하면 고쳐집니다."
  else
    ok "만들기 도구가 있어요"
  fi
fi

# ---------- 4. 열쇠 ----------
#
# "대화가 안 된다" 의 가장 흔한 원인이다. 파일이 있는지만 보지 않고,
# 안에 열쇠가 실제로 들어 있는지까지 본다.
step "4/7 열쇠가 들어갔는지 확인 중"
AUTH="$HOME/.local/share/opencode/auth.json"
MEDIA="$HOME/.config/camp/media-keys.env"
KEYERR=""
if [ ! -s "$AUTH" ]; then
  KEYERR="AI 열쇠 파일이 없어요"
elif ! grep -q '"' "$AUTH" 2>/dev/null; then
  KEYERR="AI 열쇠 파일이 비어 있어요"
elif [ ! -s "$MEDIA" ]; then
  KEYERR="그림 열쇠 파일이 없어요"
elif ! grep -q 'GEMINI_API_KEY=..' "$MEDIA" 2>/dev/null; then
  KEYERR="그림 열쇠가 비어 있어요"
fi
if [ -n "$KEYERR" ]; then
  bad "$KEYERR"
  note "이게 없으면 도우미와 대화가 안 됩니다. 설치를 다시 해 주세요."
else
  ok "열쇠가 들어갔어요"
fi

# ---------- 5. 셸 ----------
step "5/7 .sh 도구를 실행할 셸이 잡혔는지 확인 중"
SHELLPATH=""
if [ -f "$CFG/opencode.json" ] && command -v python3 >/dev/null 2>&1; then
  SHELLPATH=$(python3 -c "
import json,sys
try:
    print(json.load(open(sys.argv[1],encoding='utf-8')).get('shell',''))
except Exception:
    print('')
" "$CFG/opencode.json" 2>/dev/null)
fi
if [ -n "$SHELLPATH" ] && [ -x "$SHELLPATH" ]; then
  ok "셸이 잡혔어요"
else
  bad "셸이 안 잡혔어요"
  note "이게 없으면 그림·영상·합치기가 안 됩니다. 설치를 다시 해 주세요."
fi

# ---------- 6. 파이썬 ----------
#
# /usr/bin/python3 는 개발자도구가 없으면 껍데기다. 실행하면 설치 창이 뜨고
# 바깥 인터넷에서 1GB 를 받는다. 그래서 그 자리는 조심해서 본다.
step "6/7 파이썬이 되는지 확인 중"
py_ok() {
  case "$(command -v "$1" 2>/dev/null)" in
    /usr/bin/*) xcode-select -p >/dev/null 2>&1 || return 1 ;;
  esac
  "$1" -c "pass" >/dev/null 2>&1
}
PY=""
for c in /usr/local/bin/python3 /opt/homebrew/bin/python3 \
         /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 python3 python; do
  command -v "$c" >/dev/null 2>&1 || continue
  if py_ok "$c"; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  bad "파이썬이 없어요"
  note "그림을 한 장도 만들 수 없습니다. 설치를 다시 해 주세요."
else
  # python.org 판은 인증서를 따로 넣어야 https 가 된다.
  # 안 넣으면 그림 만들기가 전부 SSL 오류로 죽는데, 설치 때는 안 보인다.
  if "$PY" -c "
import urllib.request, urllib.error, sys
try:
    urllib.request.urlopen('https://generativelanguage.googleapis.com/', timeout=10)
except urllib.error.HTTPError:
    pass          # 응답이 왔으면 https 는 통한 것이다
except Exception:
    sys.exit(1)
" >/dev/null 2>&1; then
    ok "파이썬이 되고 인터넷도 통해요"
  else
    bad "파이썬이 인터넷에 연결되지 않아요"
    note "인증서가 빠졌거나 인터넷이 안 되는 상태입니다."
    note "터미널에 이걸 쳐 보세요:"
    note "  /Applications/Python*/Install\\ Certificates.command"
  fi
fi

# ---------- 7. 진짜로 대화가 되는가 ----------
#
# 앞의 여섯 개가 다 초록이어도 대화가 안 될 수 있다. 그래서 실제로 물어본다.
# 이게 윈도우 점검의 "AI 도우미가 연결되는지" 와 같은 항목이다.
step "7/7 도우미와 대화가 되는지 확인 중 (좀 걸려요)"
CLI=""
for c in "$BIN/opencode" opencode; do
  command -v "$c" >/dev/null 2>&1 && { CLI="$c"; break; }
done
if [ -z "$CLI" ]; then
  bad "점검용 도구(opencode)가 없어요"
else
  ANSWER=$("$CLI" run '안녕하세요' --agent 도우미 2>"$CAMPDIR/.점검오류.txt")
  ERRTEXT=$(cat "$CAMPDIR/.점검오류.txt" 2>/dev/null)
  if printf '%s' "$ANSWER" | grep -q '[가-힣]'; then
    ok "도우미가 대답했어요"
  else
    bad "도우미가 대답하지 않았어요"
    if printf '%s' "$ERRTEXT" | grep -qi 'Falling back to default agent'; then
      note "캠프 설정이 안 읽혔어요. 설치를 다시 해 주세요."
    elif printf '%s' "$ERRTEXT" | grep -qi 'auth\|api key\|401\|403'; then
      note "열쇠에 문제가 있어요. 설치를 다시 해 주세요."
    elif printf '%s' "$ERRTEXT" | grep -qi 'network\|timeout\|ENOTFOUND\|ECONN'; then
      note "인터넷이 안 되고 있어요. 와이파이를 확인해 주세요."
    else
      note "자세한 내용은 여기 있어요: $CAMPDIR/.점검오류.txt"
    fi
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  ok "다 좋아요! 캠프 시작을 눌러서 쓰면 돼요."
  exit 0
fi
bad "안 된 것이 $FAIL 개 있어요."
note "설치를 한 번 더 하면 대부분 고쳐집니다."
note "그래도 안 되면 이 창을 그대로 두고 선생님을 불러 주세요."
note "기록: $LOG"
exit 1
