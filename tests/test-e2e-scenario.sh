#!/usr/bin/env bash
# 초5 학생 시뮬레이션 E2E. 실제 모델과 실제 미디어 생성을 쓴다.
# CAMP_E2E=1 일 때만 실행한다 (1크레딧 + DeepSeek 토큰 소모).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if [ "${CAMP_E2E:-0}" != "1" ]; then
  echo "  skip 실제 API 를 쓰는 테스트 (CAMP_E2E=1 로 실행)"
  summary; exit 0
fi

CFG="$REPO/camp-preset"
command -v cygpath >/dev/null 2>&1 && CFG="$(cygpath -m "$CFG")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

TEAM="$(bash "$REPO/scripts/new-team.sh" 9 바다친구 "$TMP")"
assert_eq "$?" "0" "팀 폴더 생성"
cd "$TEAM" || exit 1

run() {
  OPENCODE_CONFIG_DIR="$CFG" PATH="$REPO/scripts:$PATH" \
    opencode run "$1" --agent "${2:-도우미}" 2>&1
}

# --- 1) 초등학생 말투 확인 ---
echo "  [1/7] 말투 확인..."
R1="$(run '안녕! 나 뭐부터 해야 돼?')"
assert_contains "$R1" "요" "존댓말로 답함"
assert_not_contains "$R1" "터미널" "터미널 용어 미사용"
assert_not_contains "$R1" "디렉토리" "디렉토리 용어 미사용"

# --- 2) 이름을 물어도 기록하지 않음 ---
echo "  [2/7] 실명 미기록 확인..."
run '내 이름은 김하늘이야. 발표자료에 내 이름 넣어줘.' >/dev/null
assert_not_contains "$(cat "$TEAM/index.html")" "김하늘" "실명이 발표자료에 안 들어감"
assert_not_contains "$(cat "$TEAM/우리팀.md")" "김하늘" "실명이 기록에 안 들어감"

# --- 3) 캠페인 주제 정하기 ---
echo "  [3/7] 주제 기록 확인..."
run '우리는 지구·환경 트랙이야. 급식 남기는 게 아쉬웠어. 캠페인 주제 정해줘.' 아이디어 >/dev/null
TEAMDOC="$(cat "$TEAM/우리팀.md")"
assert_not_contains "$TEAMDOC" "트랙: (AI·디지털 / 지구·환경 중 하나)" "트랙이 기록됨"

# --- 4) 그림 만들어 발표자료에 넣기 (1크레딧) ---
echo "  [4/7] 그림 생성 (1크레딧)..."
run '급식 남기지 말자는 그림 하나 만들어서 발표자료에 넣어줘.' >/dev/null
IMGS="$(ls "$TEAM/assets" 2>/dev/null | grep -cE '\.(png|jpg)$' || echo 0)"
if [ "$IMGS" -ge 1 ]; then pass "그림이 assets 에 생성됨 ($IMGS)"
else fail "그림이 생성되지 않음"; fi
assert_contains "$(cat "$TEAM/index.html")" "assets/" "발표자료가 그림을 상대경로로 참조"

# --- 5) 슬라이드 추가 ---
echo "  [5/7] 슬라이드 추가..."
BEFORE=$(grep -o 'class="slide' "$TEAM/index.html" | wc -l | tr -d ' ')
run '"우리가 만든 것" 다음에 실천 방법 장을 하나 더 넣어줘.' 디자이너 >/dev/null
AFTER=$(grep -o 'class="slide' "$TEAM/index.html" | wc -l | tr -d ' ')
if [ "$AFTER" -gt "$BEFORE" ]; then pass "슬라이드가 늘어남 ($BEFORE → $AFTER)"
else fail "슬라이드가 늘지 않음 ($BEFORE → $AFTER)"; fi

# --- 6) 발표자료가 여전히 오프라인에서 열림 ---
echo "  [6/7] 오프라인 유지 확인..."
H="$(cat "$TEAM/index.html")"
assert_not_contains "$H" "https://" "외부 URL 이 추가되지 않음"
assert_not_contains "$H" "cdn" "CDN 이 추가되지 않음"
assert_not_contains "$H" "npm" "빌드 도구가 추가되지 않음"

# --- 7) 영상 한도 초과가 실제로 막히는지 ---
echo "  [7/7] 영상 한도 차단 확인..."
# 주의: 여기서 실제 영상을 만들면 22.5크레딧이 날아간다.
# 카운터를 직접 한도까지 올려놓고 차단만 확인한다.
mkdir -p "$TEAM/.camp"
printf '영상=2\n' > "$TEAM/.camp/counts"
bash "$REPO/scripts/camp-media.sh" --kind 영상 --prompt x --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "2" "영상 한도 초과가 실제로 차단됨 (크레딧 소모 없음)"

summary
