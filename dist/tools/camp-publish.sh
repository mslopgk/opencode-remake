#!/usr/bin/env bash
# 창의디자인캠프 발표자료 인터넷 공개 도구.
#
# 이 스크립트의 존재 이유: 공개는 되돌릴 수 없다.
# 한번 공개된 주소는 검색엔진이 가져가고 지워도 남는다. 그래서
# "무엇을 올릴지" 를 프롬프트에 맡기지 않고 여기서 기계적으로 정한다.
# 올리는 것은 index.html 과 assets/ 뿐이다. 팀 기록장(우리팀.md)과
# 만든 횟수(.camp)와 친구별 원본(slides/)은 올리지 않는다.
#
# 사용법:
#   camp-publish.sh --team-dir <팀폴더> [--check]
#     --check  올릴 준비가 됐는지만 확인하고 실제로 올리지는 않는다
#
# 성공: 공개 주소를 stdout 에 한 줄 출력
# 실패 exit 코드:
#   2=깃허브 연결 안 됨  3=발표자료 없음  4=인자 오류
#   5=비밀번호로 보이는 것 발견  6=올리기 실패  7=조 번호 없음
set -uo pipefail

TEAM_DIR=""; CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --team-dir) TEAM_DIR="${2:-}"; shift 2 ;;
    --check)    CHECK_ONLY=1; shift ;;
    *) echo "알 수 없는 옵션이에요: $1" >&2; exit 4 ;;
  esac
done

[ -n "$TEAM_DIR" ]  || { echo "팀 폴더가 필요해요." >&2; exit 4; }
[ -d "$TEAM_DIR" ]  || { echo "팀 폴더를 찾을 수 없어요." >&2; exit 4; }

cd "$TEAM_DIR" || { echo "팀 폴더를 열 수 없어요." >&2; exit 4; }

[ -f "index.html" ] || { echo "발표자료가 아직 없어요." >&2; exit 3; }

# ── 조 번호를 읽어 주소를 정한다 ────────────────────────────────
# 주소에 한글이 들어가면 알아보기 힘든 글자로 바뀐다. 숫자만 쓴다.
# 기록장에는 "03조" 처럼 적혀 있다. 숫자만 뽑는다.
TEAM_NO="$(grep '^- 조 번호:' 우리팀.md 2>/dev/null | head -1 | sed 's/[^0-9]//g')"
case "$TEAM_NO" in
  ''|*[!0-9]*) echo "조 번호를 먼저 정해 주세요." >&2; exit 7 ;;
esac
TEAM_NO="$(printf '%02d' "$((10#$TEAM_NO))" 2>/dev/null)" || { echo "조 번호를 알아볼 수 없어요." >&2; exit 7; }
REPO="camp2026-team${TEAM_NO}"

# ── 올릴 것만 고른다 ────────────────────────────────────────────
STAGE=".camp/publish"

# ── 비밀번호로 보이는 것이 섞여 있으면 올리지 않는다 ────────────
# 공개 저장소에 열쇠가 올라가면 몇 분 만에 긁어가는 프로그램들이 있다.
scan_secrets() {
  local hits
  hits="$(grep -rIl -E 'sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
        index.html assets 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "올리면 안 되는 비밀번호 같은 것이 들어 있어요. 선생님을 불러 주세요." >&2
    exit 5
  fi
}
scan_secrets

# ── 깃허브에 연결돼 있는지 확인한다 ─────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "깃허브 도구가 없어요. 선생님을 불러 주세요." >&2
  exit 2
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "아직 깃허브에 연결되지 않았어요." >&2
  exit 2
fi

OWNER="$(gh api user -q .login 2>/dev/null)"
[ -n "$OWNER" ] || { echo "아직 깃허브에 연결되지 않았어요." >&2; exit 2; }

URL="https://${OWNER}.github.io/${REPO}/"

if [ "$CHECK_ONLY" = "1" ]; then
  printf '%s\n' "$URL"
  exit 0
fi

# ── 올릴 파일만 따로 모은다 ─────────────────────────────────────
rm -rf "$STAGE"
mkdir -p "$STAGE" || { echo "올릴 준비를 못 했어요." >&2; exit 6; }
cp index.html "$STAGE/" || { echo "올릴 준비를 못 했어요." >&2; exit 6; }
[ -d assets ] && cp -r assets "$STAGE/" 2>/dev/null
# 깃허브가 파일 이름을 건드리지 않게 한다
: > "$STAGE/.nojekyll"

# ── 저장소를 만들고 올린다 ──────────────────────────────────────
if ! gh repo view "${OWNER}/${REPO}" >/dev/null 2>&1; then
  if ! gh repo create "${OWNER}/${REPO}" --public \
        -d "2026 영남·제주권역 창의디자인캠프 ${TEAM_NO}조" >/dev/null 2>&1; then
    echo "인터넷에 올리지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
    exit 6
  fi
fi

cd "$STAGE" || { echo "올릴 준비를 못 했어요." >&2; exit 6; }
git init -q -b main >/dev/null 2>&1
# 학생 컴퓨터의 전체 설정은 건드리지 않는다. 이 폴더에만 적어 둔다.
git config user.name  "창의디자인캠프" >/dev/null 2>&1
git config user.email "camp@example.invalid" >/dev/null 2>&1
git add -A >/dev/null 2>&1
git commit -q -m "발표자료" >/dev/null 2>&1
git remote remove origin >/dev/null 2>&1
git remote add origin "https://github.com/${OWNER}/${REPO}.git" >/dev/null 2>&1

# 이 저장소에는 이 스크립트가 만든 것만 들어간다. 학생이 손으로 고칠 것이
# 없으므로, 충돌로 발표 준비가 막히지 않게 항상 새로 덮어쓴다.
if ! git push -q --force origin main >/dev/null 2>&1; then
  echo "인터넷에 올리지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
  exit 6
fi

# ── 공개 설정을 켠다 (이미 켜져 있으면 그냥 넘어간다) ───────────
gh api -X POST "repos/${OWNER}/${REPO}/pages" \
  -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1

printf '%s\n' "$URL"
