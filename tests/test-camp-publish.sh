#!/usr/bin/env bash
# camp-publish.sh 단위 테스트.
# 진짜 깃허브에 올리지 않는다. gh 와 git 을 가짜로 바꿔 끼워 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

S="$REPO/scripts/camp-publish.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_team() {
  local dir="$1" no="${2:-3}"
  bash "$REPO/scripts/new-team.sh" "$no" 테스트팀 "$dir" >/dev/null 2>&1
  printf '%s/%02d조_테스트팀' "$dir" "$no"
}

# 가짜 gh/git 을 담을 폴더. PATH 앞에 붙여 진짜 대신 쓰이게 한다.
FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
make_fake_gh() {   # $1: auth status 종료코드
  cat > "$FAKE/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "auth status") exit $1 ;;
esac
case "\$1" in
  api)  if [ "\$2" = "user" ]; then echo "학부모계정"; fi; exit 0 ;;
  repo) exit 0 ;;
esac
exit 0
EOF
  chmod +x "$FAKE/gh"
}
make_fake_git() {
  cat > "$FAKE/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE/git"
}

# --- 1) 인자 검사 ---
bash "$S" >/dev/null 2>&1
assert_eq "$?" "4" "팀 폴더를 안 주면 인자 오류"
bash "$S" --team-dir "$TMP/없는폴더" >/dev/null 2>&1
assert_eq "$?" "4" "없는 폴더는 인자 오류"

# --- 2) 발표자료가 없으면 올리지 않는다 ---
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
bash "$S" --team-dir "$EMPTY" >/dev/null 2>&1
assert_eq "$?" "3" "발표자료 없으면 3"

# --- 3) 조 번호가 없으면 주소를 못 정한다 ---
T="$(make_team "$TMP/noteam")"
sed -i 's/^- 조 번호: .*/- 조 번호: (아직 안 정함)/' "$T/우리팀.md"
bash "$S" --team-dir "$T" >/dev/null 2>&1
assert_eq "$?" "7" "조 번호 없으면 7"

# --- 4) 비밀번호 같은 것이 있으면 절대 올리지 않는다 ---
# 공개는 되돌릴 수 없으므로 깃허브 연결보다 먼저 막아야 한다.
T="$(make_team "$TMP/secret")"
printf 'sk-abcdefghijklmnopqrstuvwxyz012345\n' >> "$T/index.html"
OUT="$(bash "$S" --team-dir "$T" 2>&1)"
assert_eq "$?" "5" "발표자료에 열쇠가 있으면 5"
assert_contains "$OUT" "선생님" "학생이 이해할 안내 문구"

T="$(make_team "$TMP/secret2")"
printf 'ghp_0123456789abcdefghijklmnopqrstuvwx\n' > "$T/assets/메모.txt"
bash "$S" --team-dir "$T" >/dev/null 2>&1
assert_eq "$?" "5" "assets 안의 열쇠도 잡아냄"

# 그림 파일(이진)은 오탐하지 않아야 한다
T="$(make_team "$TMP/binok")"
printf '\x89PNG\r\n\x1a\n' > "$T/assets/그림-1.png"
PATH="$FAKE:$PATH" make_fake_gh 1
PATH="$FAKE:$PATH" bash "$S" --team-dir "$T" >/dev/null 2>&1
assert_eq "$?" "2" "그림이 있어도 열쇠로 오해하지 않음"

# --- 5) 깃허브에 연결이 안 됐을 때 ---
T="$(make_team "$TMP/noauth")"
make_fake_gh 1
OUT="$(PATH="$FAKE:$PATH" bash "$S" --team-dir "$T" 2>&1)"
assert_eq "$?" "2" "로그인 안 됐으면 2"
assert_contains "$OUT" "연결" "연결이 필요하다고 알려 줌"

# gh 자체가 없을 때
T="$(make_team "$TMP/nogh")"
OUT="$(PATH="/usr/bin:/bin" bash "$S" --team-dir "$T" 2>&1)"
assert_eq "$?" "2" "gh 가 없어도 2"

# --- 6) --check 는 주소만 알려주고 올리지 않는다 ---
T="$(make_team "$TMP/check" 7)"
make_fake_gh 0
OUT="$(PATH="$FAKE:$PATH" bash "$S" --team-dir "$T" --check 2>/dev/null)"
assert_eq "$?" "0" "--check 성공"
assert_eq "$OUT" "https://학부모계정.github.io/camp2026-team07/" "조 번호가 주소에 두 자리로 들어감"
if [ -d "$T/.camp/publish" ]; then fail "--check 는 올릴 준비를 하면 안 됨"
else pass "--check 는 아무것도 만들지 않음"; fi

# --- 7) 실제 올리기: 올릴 것만 골라 담는다 ---
T="$(make_team "$TMP/go" 12)"
make_fake_gh 0; make_fake_git
printf '<section class="slide"><h2>내 장</h2></section>\n' > "$T/slides/1번친구.html"
printf 'fake\n' > "$T/assets/포스터-1.png"
OUT="$(PATH="$FAKE:$PATH" bash "$S" --team-dir "$T" 2>/dev/null)"
assert_eq "$?" "0" "올리기 성공"
assert_eq "$OUT" "https://학부모계정.github.io/camp2026-team12/" "공개 주소 출력"

P="$T/.camp/publish"
assert_file "$P/index.html" "발표자료를 올림"
assert_file "$P/assets/포스터-1.png" "만든 그림을 올림"
assert_file "$P/.nojekyll" "파일 이름이 바뀌지 않게 표시"

# 올리면 안 되는 것들 — 개인정보와 내부 기록
if [ -e "$P/우리팀.md" ]; then fail "팀 기록장은 공개되면 안 됨"
else pass "팀 기록장은 올리지 않음"; fi
if [ -e "$P/slides" ]; then fail "친구별 원본은 공개되면 안 됨"
else pass "친구별 원본은 올리지 않음"; fi
if [ -e "$P/.camp" ]; then fail "만든 횟수 기록은 공개되면 안 됨"
else pass "만든 횟수 기록은 올리지 않음"; fi

# --- 8) 두 번 올려도 안전해야 한다 ---
OUT2="$(PATH="$FAKE:$PATH" bash "$S" --team-dir "$T" 2>/dev/null)"
assert_eq "$?" "0" "다시 올려도 성공"
assert_eq "$OUT2" "$OUT" "주소가 그대로"

# --- 9) 학생 컴퓨터의 전체 git 설정을 건드리지 않는다 ---
assert_contains "$(cat "$S")" "git config user.name" "이 폴더에만 이름을 적음"
assert_not_contains "$(cat "$S")" "git config --global" "전체 설정은 건드리지 않음"

summary
