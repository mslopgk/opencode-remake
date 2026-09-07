#!/usr/bin/env bash
# 단순 어서션 헬퍼. 외부 의존성 없음.

# ── 안전장치: 테스트는 절대 진짜 API 를 부르지 않는다 ──────────────
# 실제로 태운 적이 있다. 기본 제공자를 Higgsfield 로 바꾼 날,
# 테스트가 진짜 CLI 를 불러 92크레딧(약 $4.50)이 날아갔다.
# 모든 테스트가 이 파일을 source 하므로 여기서 한 번에 막는다.
# tests/mock 을 PATH 맨 앞에 두면 higgsfield 는 가짜가 잡힌다.
_CAMP_MOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../mock" && pwd)"
export PATH="$_CAMP_MOCK_DIR:$PATH"

# 테스트가 브라우저 창을 열지 않게 막는다. camp-media.sh 는 성공하면
# 만든 것을 브라우저로 띄우는데, 테스트가 그걸 하면 창이 쏟아진다.
export CAMP_NO_SHOW=1

_PASS=0
_FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"
  else fail "$3 (기대='$2' 실제='$1')"; fi
}

assert_contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 ('$2' 없음)" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3 ('$2' 가 있으면 안 됨)" ;;
    *) pass "$3" ;;
  esac
}

assert_file() {
  if [ -f "$1" ]; then pass "$2"; else fail "$2 (파일 없음: $1)"; fi
}

summary() {
  printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_PASS" "$_FAIL"
  [ "$_FAIL" -eq 0 ]
}
