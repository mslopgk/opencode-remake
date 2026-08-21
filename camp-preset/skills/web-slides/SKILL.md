---
name: web-slides
description: 발표자료 index.html 의 구조와 편집 규칙. 슬라이드를 추가·수정하거나 색 테마를 바꿀 때 읽는다
---

# 발표자료 편집 규칙

발표자료는 팀 폴더의 `index.html` 파일 하나다.

## 절대 규칙

- **외부 URL 을 넣지 않는다.** CDN, 웹폰트, 외부 스크립트 금지.
  캠프장 인터넷이 끊겨도 발표가 되어야 한다.
- **빌드 도구를 쓰지 않는다.** 패키지 설치, 번들러, 프레임워크 금지.
  순수 HTML/CSS/JS 만 쓴다.
- 슬라이드 전환 스크립트를 새로 만들지 않는다. 이미 있는 것을 쓴다.
- 그림·음악·영상은 `assets/` 안의 파일을 **상대경로**로 참조한다.
  절대경로를 쓰면 다른 컴퓨터에서 안 보인다.

## 슬라이드 하나의 구조

```html
<section class="slide">
  <h2>제목</h2>
  <p>내용</p>
</section>
```

- 첫 번째 슬라이드에만 `class="slide on"` 이 붙는다. 나머지는 `class="slide"`.
- 새 슬라이드는 `<div class="page">` 바로 위에 넣는다.
- 슬라이드를 추가하면 아래 스크립트가 개수를 자동으로 센다. 숫자를 직접
  고치지 않는다.

## 글 양 규칙

- 한 슬라이드에 글은 최대 5줄.
- 초등학생이 발표하며 읽을 문장이다. 짧고 쉬운 말로 쓴다.
- 제목은 `<h2>`, 본문은 `<p>` 또는 `<ul><li>`.

## 그림 넣기

```html
<section class="slide">
  <h2>우리가 만든 포스터</h2>
  <img class="media" src="assets/포스터-1.png" alt="캠페인 포스터">
</section>
```

음악은 `<audio class="media" src="assets/음악-1.wav" controls></audio>`,
영상은 `<video class="media" src="assets/영상-1.mp4" controls></video>`.

`class="media"` 를 반드시 붙인다. 크기가 화면에 맞게 조절된다.

## 색 테마 바꾸기

`<html>` 태그의 `data-theme` 값만 바꾼다.

```html
<html lang="ko" data-theme="forest">
```

쓸 수 있는 값: `ocean`(바다·파랑), `forest`(숲·초록),
`sunset`(노을·주황), `night`(밤·보라)

개별 요소에 색을 직접 넣지 않는다. 테마가 깨진다.

## 고친 뒤에

`우리팀.md` 의 "만든 것" 과 "다음에 할 일" 을 갱신한다.
학생에게는 "세 번째 장에 포스터를 넣었어요" 처럼 기술 용어 없이 알린다.
