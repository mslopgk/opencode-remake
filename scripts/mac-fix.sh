#!/bin/bash
# 맥에서 이미 설치한 캠프를 최신으로 고친다. 윈도우의 "도구 고치기" 와 같은 일.
#
# 왜 필요한가 (실측, 2026-09-05 현장):
#   설치를 끝낸 노트북에는 그 시점의 도구와 설정이 그대로 남는다.
#   캠프 도중에 고친 것들(영상 만들기, 도우미가 사진 보기, 발표자료 규칙)이
#   학생 노트북까지 가지 않는다. 설치 파일은 375MB 라 다시 받게 할 수 없다.
#   그래서 바뀐 것만 50KB 로 받아 갈아끼운다.
#
# 쓰는 법 (터미널 한 줄):
#   curl -fsSL http://192.168.0.5/mac-fix -o ~/fix.sh && bash ~/fix.sh

set -u

SERVER="${CAMP_SERVER:-__CAMP_SERVER__}"
BIN="$HOME/.local/bin"
CFG="$HOME/.config/opencode"
KEYDIR="$HOME/.config/camp"
CAMPDIR="$HOME/창의디자인캠프"
WORK="$(mktemp -d /tmp/campfix-XXXXXX)" || { echo "임시 폴더를 못 만들었어요"; exit 1; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

echo
echo "=============================================="
echo "   창의디자인캠프 도구 고치기 (맥)"
echo "=============================================="
echo

mkdir -p "$BIN" "$CFG" "$KEYDIR" "$CAMPDIR" 2>/dev/null

# ---------- 1. 받아오기 ----------
# USB 로 실행하면 옆에 있는 것을 쓴다. 없으면 내부망에서 받는다.
HERE=""
CAND="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$CAND" ] && [ -f "$CAND/tools.zip" ] && HERE="$CAND"

if [ -n "$HERE" ]; then
  echo "[진행] USB 에서 가져오는 중"
  cp -f "$HERE/tools.zip" "$WORK/tools.zip" || { echo "[실패] 파일을 못 읽었어요"; exit 1; }
else
  echo "[진행] 내려받는 중 (금방 끝나요)"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$WORK/tools.zip" "$SERVER/tools.zip"; then
    echo "[실패] 캠프 와이파이에 연결되어 있는지 확인해 주세요."
    echo "       연결돼 있는데도 안 되면 선생님을 불러 주세요."
    exit 1
  fi
fi

rm -rf "$WORK/x"; mkdir -p "$WORK/x"
if ! (ditto -x -k "$WORK/tools.zip" "$WORK/x" 2>/dev/null || unzip -q "$WORK/tools.zip" -d "$WORK/x"); then
  echo "[실패] 압축을 풀지 못했어요. 선생님을 불러 주세요."
  exit 1
fi

# ---------- 2. 갈아끼우기 ----------
CHANGED=0

# 만들기 도구
if [ -d "$WORK/x/tools" ]; then
  for F in "$WORK/x/tools/"*; do
    [ -f "$F" ] || continue
    cp -f "$F" "$BIN/" && CHANGED=$((CHANGED+1))
  done
  chmod +x "$BIN"/*.sh 2>/dev/null
fi

# 캠프 설정.
# opencode.json 은 건드리지 않는다. 설치할 때 거기에 셸 경로를 써 넣는데
# 덮어쓰면 그게 지워져서 그림·영상·합치기가 전부 죽는다.
if [ -d "$WORK/x/preset" ]; then
  for D in agent command skills; do
    [ -d "$WORK/x/preset/$D" ] || continue
    rm -rf "$CFG/$D"
    cp -R "$WORK/x/preset/$D" "$CFG/" && CHANGED=$((CHANGED+1))
  done
  if [ -f "$WORK/x/preset/AGENTS.md" ]; then
    cp -f "$WORK/x/preset/AGENTS.md" "$CFG/" && CHANGED=$((CHANGED+1))
  fi
fi

# 열쇠 (그림·영상 만들 곳이 늘어나면 이게 있어야 쓸 수 있다)
if [ -f "$WORK/x/keys/media-keys.env" ]; then
  cp -f "$WORK/x/keys/media-keys.env" "$KEYDIR/media-keys.env" && CHANGED=$((CHANGED+1))
  chmod 600 "$KEYDIR/media-keys.env" 2>/dev/null
fi

if [ "$CHANGED" -eq 0 ]; then
  echo "[실패] 고칠 것을 못 받았어요. 선생님을 불러 주세요."
  exit 1
fi
echo "[완료] $CHANGED 가지를 새것으로 바꿨어요"

# ---------- 3. 발표자료에 남은 예시 장 치우기 ----------
#
# 도우미는 새 규칙을 알아도 이미 만들어진 index.html 을 되돌아가 고치지 않는다.
# 손대지 않은 예시 장만 지운다. 학생이 고친 장은 글이 달라서 안 지워진다.
PY=""
for c in /usr/local/bin/python3 /opt/homebrew/bin/python3 \
         /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 python3; do
  command -v "$c" >/dev/null 2>&1 || continue
  case "$(command -v "$c")" in
    /usr/bin/*) xcode-select -p >/dev/null 2>&1 || continue ;;
  esac
  "$c" -c "pass" >/dev/null 2>&1 && { PY="$c"; break; }
done

if [ -n "$PY" ]; then
  "$PY" - "$HOME" <<'PYEOF'
import os, sys, glob
home = sys.argv[1]
marks = [
    "어떤 문제를 보고 안타까웠는지 적어요",
    "우리가 어떻게 하면 ○○할 수 있을까?",
    "무엇을 하는 캠페인인지",
    "여기에 우리가 만든 그림이 들어갑니다",
    "오늘부터 할 수 있는 일",
    "들어 주셔서 고맙습니다!",
]
roots = [os.path.join(home, "창의디자인캠프"), os.path.join(home, "Desktop")]
fixed = 0
for root in roots:
    if not os.path.isdir(root):
        continue
    for path in glob.glob(os.path.join(root, "**", "index.html"), recursive=True):
        try:
            with open(path, encoding="utf-8") as f:
                html = f.read()
        except Exception:
            continue
        if 'class="slide' not in html:
            continue
        before = html
        for mark in marks:
            while True:
                at = html.find(mark)
                if at < 0:
                    break
                s0 = html.rfind("<section", 0, at)
                e0 = html.find("</section>", at)
                if s0 < 0 or e0 < 0:
                    break
                e0 += len("</section>")
                # 표지(첫 장)는 남긴다. 지우면 아무것도 안 보인다.
                if html.find("<section") == s0:
                    break
                html = html[:s0] + html[e0:]
        if html != before:
            try:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(html)
                fixed += 1
            except Exception:
                pass
if fixed:
    print("[완료] 발표자료 %d개에서 빈 예시 장을 치웠어요" % fixed)
PYEOF
fi

# ---------- 4. 앱 끄기 ----------
#
# 앱이 켜져 있으면 옛 설정을 붙들고 있다. 창만 닫아도 프로세스는 남는다.
# 사람에게 "껐다 켜세요" 라고 시키지 말고 도구가 한다(실측 사고 2026-09-05).
KILLED=0
if pgrep -x "OpenCode" >/dev/null 2>&1; then
  osascript -e 'quit app "OpenCode"' >/dev/null 2>&1
  sleep 2
  pgrep -x "OpenCode" >/dev/null 2>&1 && { pkill -x "OpenCode" >/dev/null 2>&1; sleep 1; }
  KILLED=1
fi

echo
echo "=============================================="
if [ "$KILLED" = "1" ]; then
  echo "  다 고쳤어요! 캠프 앱을 껐어요."
  echo "  바탕화면의 \"캠프 시작\" 을 다시 눌러 주세요."
else
  echo "  다 고쳤어요!"
fi
echo
echo "  ★ 앱을 켜면 반드시 [새 세션] 을 눌러 주세요."
echo "    옛 대화를 이어 쓰면 고친 것이 안 먹을 수 있어요."
echo "=============================================="
echo
