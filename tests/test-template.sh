#!/usr/bin/env bash
# 발표자료 템플릿의 구조를 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

T="$REPO/template/index.html"
assert_file "$T" "index.html 존재"
assert_file "$REPO/template/우리팀.md" "우리팀.md 존재"
H="$(cat "$T" 2>/dev/null || echo '')"

assert_contains "$H" "<!doctype html>" "doctype 선언"
assert_contains "$H" 'lang="ko"' "한국어 문서"
assert_contains "$H" 'charset="utf-8"' "UTF-8 인코딩"

# 오프라인에서 반드시 열려야 한다 — 외부 리소스 금지
assert_not_contains "$H" "https://" "외부 URL 없음 (오프라인 동작)"
assert_not_contains "$H" "http://" "외부 URL 없음 (오프라인 동작)"
assert_not_contains "$H" "cdn" "CDN 참조 없음"

# 슬라이드 구조
assert_contains "$H" 'class="slide"' "slide 클래스 존재"
# 첫 장은 class="slide on" 이므로 닫는 따옴표를 포함해 세면 안 된다
N=$(grep -o 'class="slide' "$T" | wc -l | tr -d ' ')
if [ "$N" -ge 7 ]; then pass "기본 슬라이드가 7장 이상 ($N)"
else fail "기본 슬라이드가 부족 ($N, 7 이상 필요)"; fi

# 테마 4종
assert_contains "$H" ":root" "CSS 변수 루트"
for t in ocean forest sunset night; do
  assert_contains "$H" "data-theme=\"$t\"" "테마 존재: $t"
done

# 키보드 조작
assert_contains "$H" "ArrowRight" "오른쪽 화살표 조작"
assert_contains "$H" "ArrowLeft" "왼쪽 화살표 조작"

# 빌드 도구 흔적이 없어야 한다
assert_not_contains "$H" "require(" "require 없음"
assert_not_contains "$H" "import " "ES import 없음"

summary
