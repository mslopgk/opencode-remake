#!/usr/bin/env bash
# 안전장치 검사: 테스트가 진짜 API 를 부를 수 없어야 한다.
#
# 실제로 태운 적이 있다. 기본 제공자를 Higgsfield 로 바꾼 날 테스트가
# 진짜 CLI 를 불러 92크레딧(약 $4.50)이 날아갔다. 두 번은 없어야 한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

# --- 1) assert.sh 를 source 하면 가짜 higgsfield 가 잡혀야 한다 ---
WHICH="$(command -v higgsfield 2>/dev/null || true)"
assert_contains "$WHICH" "tests/mock" "테스트에서는 가짜 higgsfield 가 잡힘"

OUT="$(higgsfield account status 2>/dev/null)"
assert_contains "$OUT" "mock@example.com" "진짜 계정이 아니라 가짜가 응답"

# --- 2) 안전장치가 assert.sh 에 실제로 들어 있다 ---
A="$(cat "$REPO/tests/lib/assert.sh")"
assert_contains "$A" "tests/mock 을 PATH 맨 앞에" "안전장치에 이유가 적혀 있음"
assert_contains "$A" 'export PATH="$_CAMP_MOCK_DIR:$PATH"' "PATH 맨 앞에 mock 을 넣음"

# --- 3) camp-media.sh 를 실제로 실행하는 테스트는 안전장치가 있어야 한다 ---
# 안전한 방법은 셋 중 하나다:
#   (a) CAMP_MEDIA_FAKE_DOWNLOAD=1 로 생성을 건너뛴다
#   (b) CAMP_MEDIA_PROVIDER 를 명시해 가짜 서버로 보낸다
#   (c) CAMP_E2E=1 일 때만 도는 의도적 실물 테스트다
for f in "$REPO"/tests/test-*.sh; do
  base="$(basename "$f")"
  [ "$base" = "test-no-real-api.sh" ] && continue
  body="$(cat "$f")"

  # 문자열만 검사하는 파일은 대상이 아니다. 실제로 실행하는 것만 본다.
  echo "$body" | grep -qE '(bash|sh) +"[^"]*camp-media\.sh"|bash +"\$SCRIPT"|bash +"\$S"' || continue
  echo "$body" | grep -q "camp-media" || continue

  # bash 변수 이름에는 한글을 쓸 수 없다 (같은 실수를 두 번 했다)
  safe=0
  case "$body" in
    *CAMP_MEDIA_FAKE_DOWNLOAD*) safe=1 ;;
  esac
  case "$body" in
    *CAMP_MEDIA_PROVIDER*) safe=1 ;;
  esac
  case "$body" in
    *'CAMP_E2E:-0'*) safe=1 ;;
  esac

  if [ "$safe" = "1" ]; then pass "$base 은 진짜 생성을 막고 있음"
  else fail "$base 이 진짜 생성을 막지 않음 (가짜 모드·제공자 명시·E2E 게이트 중 하나 필요)"; fi
done

# --- 4) E2E 테스트는 기본 실행에서 반드시 건너뛰어야 한다 ---
for e2e in test-e2e-scenario.sh test-media-e2e.sh; do
  if [ -f "$REPO/tests/$e2e" ]; then
    OUT_E2E="$(bash "$REPO/tests/$e2e" 2>&1)"
    assert_contains "$OUT_E2E" "skip" "$e2e 는 기본 실행에서 건너뜀"
  fi
done

summary
