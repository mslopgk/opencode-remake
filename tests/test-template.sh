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

# CDN 은 허용한다 (캠프장 인터넷이 잘 된다).
# 대신 빌드 도구는 여전히 금지 — npm install 이 터지면 그 팀이 날아간다.
assert_not_contains "$H" "npm install" "빌드 도구 없음"

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

# 팀 협업: slides 분리 구조
if [ -d "$REPO/template/slides" ]; then pass "slides 폴더 존재"
else fail "slides 폴더 없음"; fi
assert_contains "$H" "여기에 친구들 슬라이드가 들어갑니다" "index.html 에 조립 지점 표시"
TEAMDOC="$(cat "$REPO/template/우리팀.md" 2>/dev/null || echo '')"
assert_contains "$TEAMDOC" "나는 몇 번 친구" "우리팀.md 에 내 번호 항목"

# 움직임 라이브러리와 방어 코드
assert_contains "$H" "gsap.min.js" "GSAP 을 불러옴"
assert_contains "$H" "anime.min.js" "anime.js 를 불러옴"
assert_contains "$H" "prefers-reduced-motion" "움직임 접근성 존중"
assert_contains "$H" "!window.gsap" "라이브러리가 없어도 내용이 보이게 방어"
assert_contains "$H" "animateIn" "장 등장 애니메이션 함수 존재"

# 발표 중에 글이 안 보이는 사고를 막는 3중 안전망
# (실측: 안 보이는 탭에서는 브라우저가 애니메이션을 멈춰서 opacity 0 으로 굳었다)
assert_contains "$H" "document.hidden" "안 보이는 탭에서는 애니메이션을 건너뜀"
assert_contains "$H" "무조건보이기" "인라인 스타일을 되돌리는 함수 존재"
assert_contains "$H" "1200" "1.2초 안전망 시간"
assert_contains "$H" "visibilitychange" "탭으로 돌아오면 다시 보여줌"

summary
