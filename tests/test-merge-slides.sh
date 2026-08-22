#!/usr/bin/env bash
# merge-slides.sh 단위 테스트. 결정적 동작이므로 실제 API 를 쓰지 않는다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

S="$REPO/scripts/merge-slides.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_team() {
  local dir="$1"
  bash "$REPO/scripts/new-team.sh" 5 테스트 "$dir" >/dev/null 2>&1
  echo "$dir/05조_테스트"
}

# --- 1) slides 가 비어 있으면 0 을 반환하고 발표자료를 안 건드린다 ---
T1="$(make_team "$TMP/a")"
BEFORE=$(grep -c 'class="slide' "$T1/index.html")
N="$(bash "$S" --team-dir "$T1" 2>/dev/null)"
assert_eq "$?" "0" "빈 slides 도 성공"
assert_eq "$N" "0" "합친 장 수 0"
assert_eq "$(grep -c 'class="slide' "$T1/index.html")" "$BEFORE" "발표자료가 그대로"

# --- 2) 두 명의 슬라이드를 합친다 ---
T2="$(make_team "$TMP/b")"
printf '<section class="slide">\n  <h2>1번 친구 장</h2>\n</section>\n' > "$T2/slides/1번친구.html"
printf '<section class="slide">\n  <h2>2번 친구 장</h2>\n</section>\n' > "$T2/slides/2번친구.html"
BEFORE=$(grep -c 'class="slide' "$T2/index.html")
N="$(bash "$S" --team-dir "$T2" 2>/dev/null)"
assert_eq "$N" "2" "2장 합침"
AFTER=$(grep -c 'class="slide' "$T2/index.html")
assert_eq "$AFTER" "$((BEFORE + 2))" "슬라이드가 2장 늘어남"
assert_contains "$(cat "$T2/index.html")" "1번 친구 장" "1번친구 내용 포함"
assert_contains "$(cat "$T2/index.html")" "2번 친구 장" "2번친구 내용 포함"

# --- 3) 순서가 파일명 순이어야 한다 ---
POS1=$(grep -n "1번 친구 장" "$T2/index.html" | cut -d: -f1)
POS2=$(grep -n "2번 친구 장" "$T2/index.html" | cut -d: -f1)
if [ "$POS1" -lt "$POS2" ]; then pass "1번친구가 2번친구보다 앞"
else fail "순서가 뒤바뀜 ($POS1 vs $POS2)"; fi

# --- 4) 두 번 합쳐도 중복되지 않는다 (멱등) ---
N2="$(bash "$S" --team-dir "$T2" 2>/dev/null)"
assert_eq "$N2" "2" "재실행도 2장"
assert_eq "$(grep -c 'class="slide' "$T2/index.html")" "$((BEFORE + 2))" "중복 누적 없음"
assert_eq "$(grep -c '1번 친구 장' "$T2/index.html")" "1" "1번친구 장이 한 번만"

# --- 5) 친구가 늘어나면 반영된다 ---
printf '<section class="slide">\n  <h2>3번 친구 장</h2>\n</section>\n' > "$T2/slides/3번친구.html"
N3="$(bash "$S" --team-dir "$T2" 2>/dev/null)"
assert_eq "$N3" "3" "3장으로 갱신"
assert_eq "$(grep -c 'class="slide' "$T2/index.html")" "$((BEFORE + 3))" "슬라이드 3장 증가"

# --- 6) section 태그가 없는 파일도 한 장으로 감싼다 ---
T3="$(make_team "$TMP/c")"
printf '<h2>태그 없는 내용</h2>\n<p>그래도 들어가야 해요</p>\n' > "$T3/slides/1번친구.html"
N4="$(bash "$S" --team-dir "$T3" 2>/dev/null)"
assert_eq "$N4" "1" "태그 없는 파일도 1장"
assert_contains "$(cat "$T3/index.html")" "태그 없는 내용" "내용이 들어감"
assert_contains "$(cat "$T3/index.html")" 'class="slide"' "section 으로 감싸짐"

# --- 7) 합친 뒤에도 오프라인 유지 ---
H="$(cat "$T2/index.html")"
assert_not_contains "$H" "https://" "외부 URL 없음"
assert_not_contains "$H" "cdn" "CDN 없음"

# --- 8) 인자 검증 ---
bash "$S" >/dev/null 2>&1
assert_eq "$?" "4" "인자 없으면 exit 4"
bash "$S" --team-dir "$TMP/없는팀" >/dev/null 2>&1
assert_eq "$?" "4" "없는 팀 폴더는 exit 4"

# --- 9) 조립 지점이 없으면 exit 5 ---
T4="$(make_team "$TMP/d")"
grep -v "여기에 친구들 슬라이드가 들어갑니다" "$T4/index.html" > "$T4/tmp.html" && mv "$T4/tmp.html" "$T4/index.html"
printf '<section class="slide"><h2>x</h2></section>\n' > "$T4/slides/1번친구.html"
bash "$S" --team-dir "$T4" >/dev/null 2>&1
assert_eq "$?" "5" "조립 지점 없으면 exit 5"

summary
