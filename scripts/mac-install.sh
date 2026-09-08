#!/bin/bash
# 맥에서 창의디자인캠프를 설치한다.
#
# 왜 별도인가 (2026-09-05, 행사장):
#   설치 파일은 윈도우 전용이다(.exe, PowerShell, 바로가기). 맥을 가져온
#   학생이 있어서 맥 몫을 따로 만든다.
#
# 어떻게 쓰는가 (학생이 터미널에 한 줄):
#   curl -fsSL http://192.168.0.5/mac -o ~/camp.sh && bash ~/camp.sh
#
# 왜 curl 로 받아서 실행하는가:
#   사파리로 받으면 맥이 "확인되지 않은 개발자" 딱지(quarantine)를 붙여
#   앱이 안 열린다. 터미널로 받으면 그 딱지가 안 붙는다.
#
# 왜 파이프(|bash)가 아니라 파일로 받아 실행하는가:
#   파이프로 하면 표준입력을 스크립트가 차지해서 물어보기가 안 된다.

set -u

# 서버 주소는 이 글을 준 서버가 직접 써 넣는다.
# 포트가 바뀌어도 학생이 고칠 것이 없다.
SERVER="${CAMP_SERVER:-__CAMP_SERVER__}"
WORK="$(mktemp -d /tmp/camp-XXXXXX)"
APPDIR="$HOME/Applications"
BIN="$HOME/.local/bin"
CAMPDIR="$HOME/창의디자인캠프"
LOG="$CAMPDIR/설치기록.txt"

FAILED=0

# 기록 쓰기가 실패해도 함수는 성공으로 끝나야 한다.
# 안 그러면 `... && ok "됐어요" || fail "안 됐어요"` 에서 둘 다 찍힌다.
say()  {
  printf '%s\n' "$*"
  { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "${LOG:-/dev/null}"; } 2>/dev/null
  return 0
}
step() { say "[진행] $*"; }
ok()   { say "[완료] $*"; }
note() { say "[안내] $*"; }
fail() { say "[실패] $*"; FAILED=$((FAILED+1)); }

cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

mkdir -p "$CAMPDIR" "$APPDIR" "$BIN" 2>/dev/null
: > "$LOG" 2>/dev/null

echo
echo "=============================================="
echo "   창의디자인캠프 설치 (맥)"
echo "=============================================="
echo

# ---------- 1. 이 맥이 어떤 맥인지 ----------
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
  arm64)  ARCH=arm64; GH_ARCH=arm64; CLI_ARCH=arm64 ;;
  x86_64) ARCH=x64;   GH_ARCH=amd64; CLI_ARCH=x64   ;;
  *)      fail "처음 보는 맥이에요 ($RAW_ARCH). 선생님을 불러 주세요."; exit 1 ;;
esac
OSVER="$(sw_vers -productVersion 2>/dev/null || echo '?')"
step "맥을 확인하고 있어요 (칩 $RAW_ARCH, macOS $OSVER)"

MAJOR="${OSVER%%.*}"
if [ "$MAJOR" != "?" ] && [ "$MAJOR" -lt 12 ] 2>/dev/null; then
  fail "macOS 12 이상이 필요해요. 지금은 $OSVER 예요."
  exit 1
fi
ok "맥은 괜찮아요"

# ---------- 2. 받아오기 ----------
# 이 글 옆에 준비물이 같이 있으면(USB) 그걸 쓴다. 없으면 서버에서 받는다.
HERE=""
CAND="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -n "$CAND" ] && [ -d "$CAND/mac" ] && [ -f "$CAND/camp-mac-payload.tar.gz" ]; then
  HERE="$CAND"
fi

if [ -n "$HERE" ]; then
  step "USB 에서 준비물을 가져오고 있어요"
else
  step "설치 준비물을 받고 있어요. 좀 걸려요."
  # 서버가 안 열려 있으면 여기서 끝난다. 뒤 단계가 다 무의미하므로 먼저 본다.
  if ! curl -fsS -m 15 -o /dev/null "$SERVER/" 2>/dev/null; then
    fail "설치 서버에 연결되지 않아요 ($SERVER)"
    note "노트북이 캠프 와이파이에 연결됐는지 확인해 주세요."
    exit 1
  fi
fi

# 준비물을 가져온다.
#
# USB 에서 실행하면 옆에 파일이 이미 있다. 그러면 복사만 한다.
# (USB 를 쓰면 인터넷도 내부망도 필요 없다)
get() {   # get <상대경로> <저장이름>
  if [ -n "$HERE" ] && [ -f "$HERE/$1" ]; then
    cp -f "$HERE/$1" "$WORK/$2" && return 0
  fi
  if curl -fsSL --retry 3 --retry-delay 2 -o "$WORK/$2" "$SERVER/$1"; then
    return 0
  fi
  return 1
}

get "mac/opencode-desktop-mac-$ARCH.zip" app.zip     || { fail "캠프 앱을 받지 못했어요"; exit 1; }
get "mac/opencode-darwin-$CLI_ARCH.zip"  cli.zip     || fail "점검용 도구를 받지 못했어요"
get "mac/gh-macos-$GH_ARCH.zip"          gh.zip      || fail "인터넷에 올리는 도구를 받지 못했어요"
get "camp-mac-payload.tar.gz"            payload.tgz || { fail "캠프 설정을 받지 못했어요"; exit 1; }
ok "준비물을 다 받았어요"

# ---------- 3. 캠프 앱 ----------
step "캠프 앱을 넣고 있어요"
rm -rf "$WORK/app"; mkdir -p "$WORK/app"
if ditto -x -k "$WORK/app.zip" "$WORK/app" 2>/dev/null || unzip -q "$WORK/app.zip" -d "$WORK/app"; then
  APP="$(find "$WORK/app" -maxdepth 2 -name '*.app' -print -quit)"
  if [ -n "$APP" ]; then
    NAME="$(basename "$APP")"
    rm -rf "$APPDIR/$NAME"
    if ditto "$APP" "$APPDIR/$NAME" 2>/dev/null; then
      # 인터넷에서 받은 표식을 떼 준다. 안 떼면 "손상되었습니다" 가 뜬다.
      xattr -dr com.apple.quarantine "$APPDIR/$NAME" 2>/dev/null
      ok "캠프 앱을 넣었어요"
      APP_PATH="$APPDIR/$NAME"
    else
      fail "캠프 앱을 넣지 못했어요"
    fi
  else
    fail "받은 파일 안에 앱이 없어요"
  fi
else
  fail "캠프 앱 압축을 풀지 못했어요"
fi

# ---------- 4. 점검용 도구 + 올리는 도구 ----------
step "도구를 넣고 있어요"
for pair in "cli.zip:opencode" "gh.zip:gh"; do
  Z="${pair%%:*}"; WANT="${pair##*:}"
  [ -f "$WORK/$Z" ] || continue
  rm -rf "$WORK/x-$WANT"; mkdir -p "$WORK/x-$WANT"
  ditto -x -k "$WORK/$Z" "$WORK/x-$WANT" 2>/dev/null || unzip -q "$WORK/$Z" -d "$WORK/x-$WANT" 2>/dev/null
  FOUND="$(find "$WORK/x-$WANT" -type f -name "$WANT" -perm -u+x -print -quit 2>/dev/null)"
  [ -z "$FOUND" ] && FOUND="$(find "$WORK/x-$WANT" -type f -name "$WANT" -print -quit 2>/dev/null)"
  if [ -n "$FOUND" ]; then
    cp -f "$FOUND" "$BIN/$WANT" && chmod +x "$BIN/$WANT"
    xattr -dr com.apple.quarantine "$BIN/$WANT" 2>/dev/null
  fi
done
ok "도구를 넣었어요"

# ---------- 5. 캠프 설정 + 열쇠 + 만들기 도구 ----------
step "캠프 설정을 넣고 있어요"
rm -rf "$WORK/p"; mkdir -p "$WORK/p"
if tar -xzf "$WORK/payload.tgz" -C "$WORK/p" 2>/dev/null; then
  # 프리셋
  if [ -d "$WORK/p/preset" ]; then
    CFG="$HOME/.config/opencode"
    if [ -d "$CFG" ] && [ -n "$(ls -A "$CFG" 2>/dev/null)" ]; then
      mv "$CFG" "$CFG.backup-$(date '+%Y%m%d-%H%M%S')" 2>/dev/null
      note "원래 쓰던 설정은 따로 보관했어요."
    fi
    mkdir -p "$CFG"
    cp -R "$WORK/p/preset/." "$CFG/" 2>/dev/null
  fi
  # 열쇠
  if [ -f "$WORK/p/secrets/auth.json" ]; then
    mkdir -p "$HOME/.local/share/opencode"
    cp -f "$WORK/p/secrets/auth.json" "$HOME/.local/share/opencode/auth.json"
    chmod 600 "$HOME/.local/share/opencode/auth.json" 2>/dev/null
  fi
  if [ -f "$WORK/p/secrets/media-keys.env" ]; then
    mkdir -p "$HOME/.config/camp"
    cp -f "$WORK/p/secrets/media-keys.env" "$HOME/.config/camp/media-keys.env"
    chmod 600 "$HOME/.config/camp/media-keys.env" 2>/dev/null
  fi
  # 만들기 도구
  if [ -d "$WORK/p/tools" ]; then
    cp -f "$WORK/p/tools/"* "$BIN/" 2>/dev/null
    chmod +x "$BIN"/*.sh 2>/dev/null
  fi
  # 모델 목록 (없으면 앱이 인터넷에서 4.5MB 를 받는다)
  if [ -f "$WORK/p/models.json" ]; then
    mkdir -p "$HOME/.cache/opencode"
    [ -f "$HOME/.cache/opencode/models.json" ] || cp -f "$WORK/p/models.json" "$HOME/.cache/opencode/models.json"
  fi
  # 연습 폴더
  if [ -d "$WORK/p/template" ] && [ ! -d "$CAMPDIR/연습" ]; then
    mkdir -p "$CAMPDIR/연습"
    cp -R "$WORK/p/template/." "$CAMPDIR/연습/" 2>/dev/null
  fi
  ok "캠프 설정을 넣었어요"
else
  fail "캠프 설정을 풀지 못했어요"
fi

# ---------- 5.5 파이썬 ----------
#
# 왜 여기서 하는가 (순서가 중요하다):
#   바로 아래 6번에서 opencode.json 에 셸을 써 넣는데, 그 일을 파이썬이 한다.
#   파이썬이 없는 맥에서는 6번이 통째로 건너뛰어지고, 그러면 앱이
#   camp-media.sh 를 못 찾아 그림이 한 장도 안 나온다.
#   윈도우에서 겪은 것과 똑같은 사고다. 그래서 셸을 잡기 전에 확보한다.
step "파이썬이 있는지 확인 중"
# 맥에는 개발자도구가 없어도 /usr/bin/python3 가 "있다". 그건 껍데기다.
# 실행하면 "개발자 도구를 설치할까요?" 창이 뜨고, 학생이 누르면 바깥
# 회선에서 1GB 를 받는다. 행사장 회선이 그걸 못 견딘다.
# 윈도우의 WindowsApps 껍데기 파이썬과 똑같은 함정이다.
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
  # xcode-select --install 은 바깥 인터넷에서 1GB 넘게 받는다.
  # 행사장 회선이 100Mbps 라 여럿이 하면 회선이 죽는다.
  # 파이썬 설치 파일은 44MB 라 USB·내부망으로 주면 금방 끝난다.
  # 관리자 계정이라야 깔린다. 아니면 sudo 가 세 번 묻고 죽는데
  # 그 이유가 화면에 안 남는다. 그래서 먼저 확인한다.
  IS_ADMIN=0
  if /usr/bin/dscl . -read /Groups/admin GroupMembership 2>/dev/null |
       tr " " "\n" | grep -qx "$(id -un)"; then IS_ADMIN=1; fi

  if [ "$IS_ADMIN" != "1" ]; then
    fail "이 맥에서는 파이썬을 깔 수 없어요 (관리자 계정이 아니에요)."
    note "부모님 계정(관리자)으로 로그인해서 다시 해 주세요."
  elif get "mac/python-3.12.10-macos11.pkg" python.pkg; then
    echo
    note "이제 맥 로그인 비밀번호를 칩니다."
    note "치는 동안 화면에는 아무것도 안 보여요. 그냥 치고 엔터를 누르세요."
    if sudo -v; then
      if sudo installer -pkg "$WORK/python.pkg" -target / >>"$LOG" 2>&1; then
        export PATH="/usr/local/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"
        for c in /usr/local/bin/python3 /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 python3; do
          command -v "$c" >/dev/null 2>&1 || continue
          if py_ok "$c"; then PY="$c"; break; fi
        done
        # python.org 판은 인증서를 따로 넣어야 https 가 된다.
        # 안 넣으면 그림 만들기가 전부 SSL 오류로 죽는다.
        # 설치 때는 안 보이고 캠프 당일에만 보이는 사고다.
        CERT=$(ls -1 /Applications/Python*/Install*Certificates.command 2>/dev/null | head -1)
        if [ -n "$CERT" ]; then
          "$CERT" >>"$LOG" 2>&1 || note "인증서를 넣지 못했어요."
        fi
      else
        fail "파이썬 설치가 실패했어요."
      fi
    else
      fail "비밀번호 확인이 안 됐어요."
    fi
  fi
fi
if [ -n "$PY" ]; then ok "파이썬이 있어요 ($($PY -V 2>&1))"; else fail "파이썬을 준비하지 못했어요"; fi

# ---------- 6. 도구를 찾을 수 있게 셸을 잡아 준다 ----------
#
# 왜 필요한가: 맥에서 파인더로 연 앱은 ~/.zshrc 의 PATH 를 물려받지 않는다.
# 그러면 앱이 camp-media.sh 를 못 찾아 그림이 한 장도 안 나온다.
# 윈도우에서 셸을 잡아 준 것과 같은 문제이고, 같은 방법으로 푼다.
step ".sh 도구를 실행할 셸을 잡고 있어요"
mkdir -p "$HOME/.config/camp"
SHELLWRAP="$HOME/.config/camp/campshell"
cat > "$SHELLWRAP" <<'WRAP'
#!/bin/bash
# 캠프 도구가 있는 곳을 PATH 에 넣고 진짜 셸을 부른다.
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"

# 프리셋 글은 도구를 "$LOCALAPPDATA/Programs/camp-tools/camp-media.sh" 로 부른다.
# 윈도우에만 있는 변수라 맥에서는 빈 경로가 되고, 그림·영상·합치기·올리기가
# 전부 "No such file or directory" 로 죽는다(실측 확인).
# 프리셋을 맥용으로 따로 고치면 두 벌을 관리해야 하므로, 맥에서 그 경로가
# 통하게 만들어 준다. 프리셋은 윈도우와 한 글자도 다르지 않다.
export LOCALAPPDATA="$HOME/.local"
exec /bin/bash "$@"
WRAP
chmod +x "$SHELLWRAP"

# 프리셋이 부르는 그 경로를 실제로 만들어 준다.
mkdir -p "$HOME/.local/Programs"
rm -f "$HOME/.local/Programs/camp-tools"
ln -s "$BIN" "$HOME/.local/Programs/camp-tools" 2>/dev/null

CFGJSON="$HOME/.config/opencode/opencode.json"
if [ -f "$CFGJSON" ] && [ -n "$PY" ]; then
  "$PY" - "$CFGJSON" "$SHELLWRAP" <<'PYEOF' && ok "셸을 잡았어요" || fail "셸을 잡지 못했어요. 그림 만들기가 안 될 수 있어요."
import json, sys
path, shell = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    cfg = json.load(f)
cfg['shell'] = shell
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PYEOF
else
  fail "셸을 잡지 못했어요. 그림 만들기가 안 될 수 있어요."
fi

# PATH 를 터미널에서도 쓸 수 있게 (있으면 넘어간다)
# 깨끗한 맥에는 .zshrc 도 .bash_profile 도 없다. 없으면 만들어서 넣는다.
# "있으면 넘어간다" 로 두면 새 맥에서는 PATH 가 영영 안 들어간다.
for RC in "$HOME/.zshrc" "$HOME/.bash_profile"; do
  [ -e "$RC" ] || : > "$RC"
  grep -q 'camp: .local/bin' "$RC" 2>/dev/null && continue
  printf '\n# camp: .local/bin\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
done

# ---------- 6.5 점검·지우기 도구 ----------
#
# 왜 필요한가 (실측, 2026-09-05 현장): 맥 한 대에서 "설치는 됐는데 대화가
# 안 된다" 가 나왔는데, 맥에는 점검이 없어서 무엇이 빠졌는지 알아낼 방법이
# 하나도 없었다. 윈도우에는 "점검" 아이콘이 있다. 맥에도 둔다.
step "점검·지우기 도구를 넣고 있어요"
for T in mac-check.sh mac-uninstall.sh mac-fix.sh; do
  if get "$T" "$T"; then
    cp -f "$WORK/$T" "$BIN/$T" && chmod +x "$BIN/$T"
  fi
done

# 바탕화면에서 두 번 눌러 쓸 수 있게 한다.
# 여기서 직접 만들기 때문에 "확인되지 않은 개발자" 딱지가 안 붙는다.
if [ -f "$BIN/mac-check.sh" ]; then
  cat > "$HOME/Desktop/점검.command" <<CMD
#!/bin/bash
bash "\$HOME/.local/bin/mac-check.sh"
echo
echo "이 창은 닫아도 됩니다."
CMD
  chmod +x "$HOME/Desktop/점검.command"
fi
if [ -f "$BIN/mac-fix.sh" ]; then
  cat > "$HOME/Desktop/도구 고치기.command" <<CMD
#!/bin/bash
bash "\$HOME/.local/bin/mac-fix.sh"
echo
echo "이 창은 닫아도 됩니다."
CMD
  chmod +x "$HOME/Desktop/도구 고치기.command"
fi
if [ -f "$BIN/mac-uninstall.sh" ]; then
  cat > "$HOME/Desktop/캠프 지우기.command" <<CMD
#!/bin/bash
bash "\$HOME/.local/bin/mac-uninstall.sh"
echo
echo "이 창은 닫아도 됩니다."
CMD
  chmod +x "$HOME/Desktop/캠프 지우기.command"
fi
ok "점검·지우기 도구를 넣었어요"

# ---------- 7. 바탕화면 ----------
step "바탕화면에 아이콘을 놓고 있어요"
if [ -n "${APP_PATH:-}" ]; then
  rm -f "$HOME/Desktop/캠프 시작" 2>/dev/null
  ln -s "$APP_PATH" "$HOME/Desktop/캠프 시작" 2>/dev/null && ok "바탕화면에 아이콘을 놓았어요" \
    || note "아이콘을 놓지 못했어요. 응용 프로그램 폴더에서 열면 돼요."
fi

# ---------- 8. 점검 ----------
echo
step "설치가 잘 됐는지 확인할게요"

CHECK_FAIL=0
c_ok()   { say "[완료] $*"; }
c_fail() { say "[실패] $*"; CHECK_FAIL=$((CHECK_FAIL+1)); }

step "1/5 캠프 앱이 있는지 확인 중"
if [ -n "${APP_PATH:-}" ] && [ -d "$APP_PATH" ]; then c_ok "캠프 앱이 있어요"; else c_fail "캠프 앱이 없어요"; fi

step "2/5 캠프 설정이 들어갔는지 확인 중"
AG=$(ls -1 "$HOME/.config/opencode/agent" 2>/dev/null | wc -l | tr -d ' ')
CM=$(ls -1 "$HOME/.config/opencode/command" 2>/dev/null | wc -l | tr -d ' ')
if [ "${AG:-0}" -ge 4 ] && [ "${CM:-0}" -ge 11 ]; then
  c_ok "캠프 설정이 들어갔어요 (도우미 $AG, 명령 $CM)"
else
  c_fail "캠프 설정이 덜 들어갔어요 (도우미 ${AG:-0}/4, 명령 ${CM:-0}/11)"
fi

step "3/5 만들기 도구가 있는지 확인 중"
MISS=""
for t in camp-media.sh merge-slides.sh merge-slides.py camp-publish.sh media-gen.py camp-usage.sh; do
  [ -f "$BIN/$t" ] || MISS="$MISS $t"
done
if [ -z "$MISS" ]; then c_ok "만들기 도구가 있어요"; else c_fail "만들기 도구가 없어요 ($MISS)"; fi

step "4/5 열쇠가 들어갔는지 확인 중"
if [ -s "$HOME/.local/share/opencode/auth.json" ] && [ -s "$HOME/.config/camp/media-keys.env" ]; then
  c_ok "열쇠가 들어갔어요"
else
  c_fail "열쇠가 안 들어갔어요"
fi

step "5/5 파이썬이 있는지 확인 중"
if [ -n "$PY" ]; then
  c_ok "파이썬이 있어요 ($($PY -V 2>&1))"
else
  c_fail "파이썬이 없어요"
  note "파이썬이 없으면 그림을 만들 수 없어요. 선생님을 불러 주세요."
fi

echo
if [ "$CHECK_FAIL" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
  ok "준비 끝! 바탕화면의 '캠프 시작' 을 두 번 누르면 돼요."
  note "(맥은 앱을 처음 켤 때 준비물을 조금 더 받아요. 좀 걸릴 수 있어요)"
  exit 0
fi

fail "안 된 것이 있어요."
note "이 창을 그대로 두고 선생님을 불러 주세요."
note "기록은 $LOG 에 있어요."
exit 1
