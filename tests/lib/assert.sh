#!/usr/bin/env bash
# 단순 어서션 헬퍼. 외부 의존성 없음.
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
