---
name: web-slides
description: 발표자료 index.html 의 구조와 편집 규칙. 슬라이드를 추가·수정하거나 색 테마를 바꿀 때 읽는다
---

# 발표자료 편집 규칙

발표자료는 팀 폴더의 `index.html` 파일 하나다.

## 절대 규칙

- **CDN 은 써도 된다.** 애니메이션 라이브러리·웹폰트를 불러와도 좋다.
  캠프장 인터넷은 잘 된다.
- **빌드 도구는 쓰지 않는다.** 패키지 설치, 번들러, 프레임워크 금지.
  순수 HTML/CSS/JS 에 CDN 스크립트만 얹는다.
  (인터넷과 무관한 규칙이다 — `npm install` 이 한 번 터지면 그 팀은
  5시간 안에 발표자료를 못 만든다)
- 슬라이드 전환 스크립트를 새로 만들지 않는다. 이미 있는 것을 쓴다.
- 그림·음악·영상은 `assets/` 안의 파일을 **상대경로**로 참조한다.
  절대경로를 쓰면 다른 컴퓨터에서 안 보인다.

## 팀으로 만들 때는 자기 파일만 고친다

한 팀은 4명이고 각자 노트북이 따로다. 같은 `index.html` 을 여러 명이 고치면
합칠 때 충돌이 나서 되돌릴 수 없다.

- 학생은 `우리팀.md` 의 "나는 몇 번 친구" 를 보고 **`slides/N번친구.html` 만**
  만들고 고친다
- 그 파일에는 `<section class="slide">` 만 넣는다. `<html>`·`<head>`·`<style>` 은
  넣지 않는다 (`index.html` 의 것을 그대로 물려받는다)
- 합치기는 `$LOCALAPPDATA/Programs/camp-tools/merge-slides.sh` 가 한다. **직접 `index.html` 을 편집해 합치지 마라**
  (느리고 결과가 들쭉날쭉하다 — 실측으로 확인했다)
- 그림·음악·영상은 `assets/` 에 그대로 두고 상대경로로 참조한다.
  파일명은 래퍼가 번호를 붙이므로 겹치지 않는다

## 모양과 움직임은 `slide-design` 스킬에

색·글자 크기·여백·애니메이션(GSAP·anime.js)은 `slide-design` 스킬에 있다.
발표자료를 멋있게 만들어 달라는 요청을 받으면 그 스킬을 읽는다.

**등장 애니메이션은 템플릿에 이미 들어 있다.** 장을 넘길 때마다 요소가
아래에서 올라온다. 학생이 "움직이게 해줘" 라고 하면 이미 되고 있다고
알려주고 특별한 효과를 원하는지 물어본다.

## 지켜야 하는 것은 딱 이것뿐이다

합치기가 되려면 한 장이 `<section>` 으로 싸여 있으면 된다. 그게 전부다.

```html
<section class="slide">
  ... 여기 안은 자유다 ...
</section>
```

- 첫 번째 슬라이드에만 `class="slide on"` 이 붙는다. 나머지는 `class="slide"`.
- 새 슬라이드는 `<div class="page">` 바로 위에 넣는다.
- 슬라이드를 추가하면 아래 스크립트가 개수를 자동으로 센다. 숫자를 직접
  고치지 않는다.

## `<section>` 안은 마음대로 짜도 된다

**"제목 하나 + 글 몇 줄" 만 만들지 마라.** 그렇게 하면 열다섯 조가 전부
똑같이 생긴 발표자료를 낸다. 조마다 달라야 한다.

`<section>` 안에는 무엇을 넣어도 된다. 예를 들면:

- 그림을 화면 가득 깔고 글자를 그 위에 얹기
- 왼쪽엔 그림, 오른쪽엔 설명 (2단)
- 숫자 하나만 아주 크게
- 사진 여러 장을 격자로 늘어놓기
- 말풍선, 화살표, 순서도
- 표, 그래프 (직접 그린 막대여도 좋다)
- 글자만으로 꽉 채운 표지

**자기 `<section>` 안에는 `<style>` 을 넣어도 된다.** 그 장에만 적용되는
색·배치를 만들 수 있다. 다른 친구 장에는 영향이 없다.
(`<section>` 밖에 쓴 것은 합칠 때 사라진다. 반드시 안에 넣는다)

```html
<section class="slide">
  <style>
    .my-hero { display:grid; grid-template-columns: 1fr 1fr; gap: 4vmin; }
  </style>
  <div class="my-hero"> ... </div>
</section>
```

학생이 "어떻게 만들까?" 하고 물으면 **서로 다른 짜임 두세 개를 그려서
보여주고 고르게 한다.** 먼저 정해 주지 마라.

## 남아 있는 예시 장은 지운다

`index.html` 을 처음 열면 표지 한 장만 들어 있다. 그 표지의
`캠페인 이름을 여기에` 와 `00조 팀이름` 은 **반드시 조 것으로 바꾼다.**

예전에 만든 팀 폴더에는 예시 장이 여러 개 남아 있을 수 있다
(`우리가 찾은 문제`, `우리의 질문`, `이렇게 실천해요` 같은 것들).
조가 자기 장을 만들었으면 **그 예시 장들은 지운다.** 남겨 두면
발표할 때 빈 껍데기 장이 중간에 끼어 나온다.

## 사진과 영상을 배경으로 크게 써라

이게 제일 중요하다. **글자만 가운데 놓인 장을 만들지 마라.** 밋밋하고,
발표할 때 사람들이 안 본다. 우리가 만든 그림과 영상이 주인공이다.

`assets/` 에 있는 것을 화면 가득 깔고 그 위에 글자를 얹는다.
아래는 그대로 복사해서 파일 이름만 바꾸면 되는 것들이다.

### 사진을 배경으로 (가장 많이 쓴다)

```html
<section class="slide" style="background:url('assets/그림-1.jpg') center/cover; padding:0;">
  <div style="position:absolute; inset:0; background:rgba(0,0,0,.45);"></div>
  <div style="position:relative;">
    <h1 style="color:#fff; text-shadow:0 .4vh 2vh rgba(0,0,0,.6);">바다를 지켜요</h1>
    <p style="color:#fff;">3조 바다지킴이</p>
  </div>
</section>
```

검은 막(`rgba(0,0,0,.45)`)은 글자를 읽히게 한다. 사진이 밝으면 숫자를
올리고, 어두우면 내린다. 글자가 안 읽히면 아무 소용이 없다.

### 영상을 배경으로

```html
<section class="slide" style="padding:0; overflow:hidden;">
  <video src="assets/영상-1.mp4" autoplay muted loop playsinline
         style="position:absolute; inset:0; width:100%; height:100%; object-fit:cover;"></video>
  <div style="position:absolute; inset:0; background:rgba(0,0,0,.4);"></div>
  <div style="position:relative;">
    <h1 style="color:#fff;">우리가 만든 영상</h1>
  </div>
</section>
```

`muted` 를 빼면 브라우저가 자동재생을 막는다. 반드시 넣는다.

### 사진 반, 글 반

```html
<section class="slide" style="padding:0;">
  <div style="position:absolute; inset:0; display:grid; grid-template-columns:1fr 1fr;">
    <div style="background:url('assets/그림-2.jpg') center/cover;"></div>
    <div style="display:flex; flex-direction:column; justify-content:center; padding:6vh 5vw; text-align:left;">
      <h2>이런 문제가 있어요</h2>
      <p>바닷가에 쓰레기가 많아요.</p>
    </div>
  </div>
</section>
```

### 사진 여러 장 깔기

```html
<section class="slide" style="padding:0;">
  <div style="position:absolute; inset:0; display:grid; grid-template-columns:repeat(3,1fr); gap:.6vh;">
    <img src="assets/그림-1.jpg" style="width:100%; height:100%; object-fit:cover;">
    <img src="assets/그림-2.jpg" style="width:100%; height:100%; object-fit:cover;">
    <img src="assets/그림-3.jpg" style="width:100%; height:100%; object-fit:cover;">
  </div>
  <h2 style="position:relative; color:#fff; text-shadow:0 .4vh 2vh #000;">우리가 만든 것들</h2>
</section>
```

### 기억할 것

- `padding:0` 을 주면 화면 끝까지 채워진다. 안 주면 가장자리에 여백이 남는다.
- 배경 위 글자는 **흰색 + 그림자**가 거의 항상 잘 읽힌다.
- 파일 이름은 `assets/` 폴더를 열어 실제로 있는 것을 쓴다. 지어내지 마라.
- 그림이 아직 없으면 먼저 만들자고 권한다. 빈 화면에 글자만 넣지 마라.

## 글 양

- 초등학생이 발표하며 읽을 문장이다. 짧고 쉬운 말로 쓴다.
- 한 장에 글이 너무 많으면 읽다가 발표가 끝난다. 대여섯 줄을 넘기면
  두 장으로 나누자고 권한다. (규칙이 아니라 권유다)
- 태그는 자유다. 제목에 `<h1>` 을 써도 되고, 글자 대신 그림만 있는 장도 좋다.

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
