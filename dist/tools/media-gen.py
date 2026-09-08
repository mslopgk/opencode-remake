#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""창의디자인캠프 미디어 생성 — 제공자별 실제 호출.

셸이 아니라 파이썬인 이유: 프롬프트에 따옴표가 들어가면 셸에서 JSON 을
안전하게 만들기 어렵고, Cloudflare 는 그림을 base64 로 돌려준다.
merge-slides.py 와 같은 이유다.

사용법:
  media-gen.py --provider cloudflare --model <id> --prompt <글> --out <파일>
               [--steps 4]
  media-gen.py --provider fal --model <id> --prompt <글> --out <파일>
               [--seconds 5]

성공: 파일을 쓰고 exit 0
실패: 사람이 읽을 이유를 stderr 에 쓰고 exit 1
"""
import argparse
import base64
import random
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Windows 파이썬은 stderr 를 콘솔 코드페이지(cp949)로 쓴다.
# 그러면 셸에서 한국어 메시지를 패턴으로 못 잡는다 — "열쇠가 없어요" 를
# 구분하지 못해 exit 6 이 절대 나오지 않았다(실측). UTF-8 로 못박는다.
# 이 프로젝트는 인코딩으로 세 번째 당했다.
for _s in ("stdout", "stderr"):
    _f = getattr(sys, _s, None)
    if _f is not None and hasattr(_f, "buffer"):
        try:
            setattr(sys, _s, io.TextIOWrapper(_f.buffer, encoding="utf-8",
                                              errors="replace", line_buffering=True))
        except Exception:
            pass

TIMEOUT = 120


def ascii확인(값, 이름):
    """열쇠에 한글·깨진 글자가 섞이면 urllib 이 알 수 없는 말로 죽는다.
    이 프로젝트는 인코딩으로 이미 두 번 당했다. 먼저 걸러 낸다."""
    try:
        값.encode("ascii")
    except UnicodeEncodeError:
        실패("%s 가 깨졌어요. 선생님을 불러 주세요." % 이름)
    return 값


def 실패(메시지):
    sys.stderr.write(메시지 + "\n")
    sys.exit(1)


# 다시 해 볼 만한 실패인지 본다.
#   429 = 너무 많이 몰림, 5xx = 서버 쪽 일시 장애
# 학생 63명이 같은 열쇠로 동시에 그림을 만들면 429 가 쏟아진다.
# 재시도가 없으면 그 학생들은 1초 만에 "실패" 를 보고 끝난다.
다시할코드 = (429, 500, 502, 503, 504)
최대시도 = 5

class 할당량참(Exception):
    """이 모델의 할당량이 찼다. 다른 모델로 넘어가라는 신호."""
    pass


def 요청(url, data=None, headers=None, method=None, timeout=TIMEOUT, 할당량알림=False):
    """할당량알림=True 면 429 를 만났을 때 기다리지 않고 곧바로 알린다.

    영상은 모델이 여럿이라 한 모델이 막히면 다음 모델로 넘어가는 편이
    빠르다. 그 자리에서 30초씩 기다렸다가 결국 실패하면 학생만 지친다.
    """
    마지막 = None
    for 시도 in range(1, 최대시도 + 1):
        req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            본문 = ""
            try:
                본문 = e.read().decode("utf-8", "replace")[:300]
            except Exception:
                pass
            if e.code == 429 and 할당량알림:
                raise 할당량참()
            if e.code not in 다시할코드 or 시도 == 최대시도:
                # 학생에게는 서버 원문(영어 JSON)을 보여주지 않는다.
                # 기록에는 남기되, 말은 아이가 알아들을 수 있게 한다.
                if 본문:
                    sys.stderr.write("(기록) HTTP %s %s" % (e.code, 본문) + chr(10))
                if e.code == 429:
                    raise RuntimeError("친구들이 한꺼번에 만들고 있어요. 조금 뒤에 다시 해 볼까요?")
                if e.code in (400, 401, 403):
                    # 열쇠가 죽었거나 요청이 틀렸다. 다시 해도 결과가 같다.
                    # "잠시 뒤에 다시" 로 숨기면 63명이 영문도 모르고 반복한다.
                    # camp-media.sh 가 이 말을 보고 종료코드 6(열쇠 문제)을 낸다.
                    raise RuntimeError("만들기 열쇠가 없어요. 선생님을 불러 주세요.")
                raise RuntimeError("만들지 못했어요. 잠시 뒤에 다시 해 볼까요?")
            # 서버가 언제 다시 오라고 알려주면 그 말을 따른다
            쉼 = None
            try:
                v = e.headers.get("Retry-After") if e.headers else None
                if v:
                    쉼 = float(v)
            except Exception:
                쉼 = None
            if 쉼 is None:
                쉼 = min(2 ** 시도, 16)
            # 63명이 똑같은 초에 다시 몰리지 않게 조금씩 흩는다
            쉼 = 쉼 + random.uniform(0, 3)
            마지막 = e
            time.sleep(쉼)
        except Exception as e:
            if 시도 == 최대시도:
                raise RuntimeError("인터넷이 잠깐 끊겼어요. 다시 해 볼까요?")
            마지막 = e
            time.sleep(min(2 ** 시도, 16) + random.uniform(0, 3))
    raise RuntimeError("만들지 못했어요. 잠시 뒤에 다시 해 볼까요?")


def cloudflare(model, prompt, out, steps):
    계정 = os.environ.get("CF_ACCOUNT_ID", "").strip()
    토큰 = os.environ.get("CF_API_TOKEN", "").strip()
    if not 계정 or not 토큰:
        실패("그림 만들기 열쇠가 없어요.")
    ascii확인(계정, "그림 만들기 계정 번호")
    ascii확인(토큰, "그림 만들기 열쇠")

    바탕 = os.environ.get("CF_API_BASE", "https://api.cloudflare.com/client/v4")
    url = "%s/accounts/%s/ai/run/%s" % (바탕.rstrip("/"), 계정, model)
    몸통 = json.dumps({"prompt": prompt, "steps": steps}).encode("utf-8")
    머리 = {"Authorization": "Bearer " + 토큰, "Content-Type": "application/json"}

    raw = 요청(url, data=몸통, headers=머리, method="POST")

    # Cloudflare 는 성공해도 success=false 로 오류를 담아 보낼 수 있다.
    try:
        답 = json.loads(raw.decode("utf-8"))
    except Exception:
        # 일부 모델은 이미지 바이너리를 그대로 준다
        if raw[:8].startswith(b"\x89PNG") or raw[:3] == b"\xff\xd8\xff":
            with open(out, "wb") as f:
                f.write(raw)
            return
        실패("그림을 알아볼 수 없어요.")

    if isinstance(답, dict) and 답.get("success") is False:
        오류 = 답.get("errors") or [{}]
        실패("그림을 만들지 못했어요: %s" % (오류[0].get("message", "알 수 없는 이유")))

    결과 = 답.get("result", 답) if isinstance(답, dict) else {}
    b64 = 결과.get("image") if isinstance(결과, dict) else None
    if not b64:
        실패("그림이 오지 않았어요.")

    try:
        데이터 = base64.b64decode(b64)
    except Exception:
        실패("그림을 알아볼 수 없어요.")
    if not 데이터:
        실패("그림이 비어 있어요.")
    with open(out, "wb") as f:
        f.write(데이터)


def _url찾기(값):
    """중첩된 응답 어디에 있든 파일 주소를 찾아낸다."""
    if isinstance(값, str) and 값.startswith("http"):
        return 값
    if isinstance(값, dict):
        for 열쇠 in ("url", "images", "video", "audio", "file"):
            if 열쇠 in 값:
                찾음 = _url찾기(값[열쇠])
                if 찾음:
                    return 찾음
        for v in 값.values():
            찾음 = _url찾기(v)
            if 찾음:
                return 찾음
    if isinstance(값, list):
        for v in 값:
            찾음 = _url찾기(v)
            if 찾음:
                return 찾음
    return None


def fal열쇠들():
    """쓸 수 있는 fal 열쇠를 모아 섞어서 돌려준다.

    왜 여러 개인가 (실측, 2026-09-05 현장):
      만드는 양은 넉넉한데 "1분에 몇 번" 이 걸린다. 학생 60명이 몰리면
      한 열쇠로는 곧바로 막힌다. 열쇠를 여러 개 두고 매번 다른 것부터
      쓰면 그 제한을 나눠 받는다.
    """
    모음 = []
    여러개 = os.environ.get("FAL_KEYS", "")
    for k in 여러개.split(","):
        k = k.strip()
        if k and k not in 모음:
            모음.append(k)
    하나 = os.environ.get("FAL_KEY", "").strip()
    if 하나 and 하나 not in 모음:
        모음.append(하나)
    # 63명이 동시에 첫 번째 열쇠로 몰리지 않게 섞는다.
    random.shuffle(모음)
    return 모음


def fal(model, prompt, out, extra):
    열쇠목록 = fal열쇠들()
    if not 열쇠목록:
        실패("영상 만들기 열쇠가 없어요.")
    for k in 열쇠목록:
        ascii확인(k, "영상 만들기 열쇠")
    열쇠 = 열쇠목록[0]

    머리 = {"Authorization": "Key " + 열쇠, "Content-Type": "application/json"}

    # 모델마다 받는 입력이 다르다(영상은 duration, 그림은 resolution 등).
    # 값은 camp-media.sh 가 정한 고정 문자열이고 학생 입력이 아니다.
    입력 = {"prompt": prompt}
    if extra:
        try:
            추가 = json.loads(extra)
        except Exception:
            실패("만들기 설정을 알아볼 수 없어요.")
        if isinstance(추가, dict):
            입력.update(추가)
    몸통 = json.dumps(입력).encode("utf-8")

    바탕 = os.environ.get("FAL_QUEUE_BASE", "https://queue.fal.run")

    # 요청수 제한(429)에 걸리면 기다리지 않고 다음 열쇠로 넘어간다.
    # 기다렸다 같은 열쇠로 다시 하면 또 막힌다.
    raw = None
    막힌수 = 0
    for i, k in enumerate(열쇠목록):
        머리["Authorization"] = "Key " + k
        마지막이냐 = (i == len(열쇠목록) - 1)
        try:
            raw = 요청(바탕.rstrip("/") + "/" + model, data=몸통,
                      headers=머리, method="POST", 할당량알림=(not 마지막이냐))
            if i > 0:
                sys.stderr.write("(기록) 열쇠 %d개가 막혀서 %d번째 열쇠로 만들었어요"
                                 % (막힌수, i + 1) + chr(10))
            break
        except 할당량참:
            막힌수 += 1
            continue
    if raw is None:
        실패("친구들이 한꺼번에 만들고 있어요. 조금 뒤에 다시 해 볼까요?")

    올린것 = json.loads(raw.decode("utf-8"))
    상태주소 = 올린것.get("status_url")
    결과주소 = 올린것.get("response_url")
    if not 상태주소 or not 결과주소:
        실패("영상 만들기를 시작하지 못했어요.")

    def 작업끄기():
        """기다리기를 그만둘 때 저쪽 작업도 꺼 준다.

        왜 (실측, 2026-09-05): 우리가 포기해도 fal 은 계속 만들고 요금을 매긴다.
        학생은 실패 화면을 보는데 돈은 나가는, 제일 나쁜 조합이다.
        게다가 그 작업이 자리를 잡고 있어서 다른 조가 뒤에서 기다리게 된다.
        """
        끌주소 = 올린것.get("cancel_url")
        if not 끌주소:
            return
        try:
            요청(끌주소, headers=머리, method="PUT", timeout=15)
        except Exception:
            pass

    # 5초짜리 영상은 40초쯤이면 나온다(실측). 8분이 지나도 안 나오면
    # 무언가 잘못된 것이다. 20분씩 기다리면 학생이 그 앞에서 굳는다.
    간격 = float(os.environ.get("CAMP_MEDIA_POLL_SEC", "5"))
    마감 = time.time() + float(os.environ.get("CAMP_MEDIA_MAX_WAIT_SEC", "480"))
    while time.time() < 마감:
        time.sleep(간격)
        상태 = json.loads(요청(상태주소, headers=머리).decode("utf-8"))
        s = 상태.get("status")
        if s == "COMPLETED":
            break
        if s in ("FAILED", "CANCELLED", "ERROR"):
            실패("영상을 만들지 못했어요.")
    else:
        작업끄기()
        실패("영상 만들기가 너무 오래 걸려요. 다시 해 볼까요?")

    결과 = json.loads(요청(결과주소, headers=머리).decode("utf-8"))
    주소 = _url찾기(결과)
    if not 주소:
        실패("영상이 오지 않았어요.")

    데이터 = 요청(주소, timeout=300)
    if not 데이터:
        실패("영상이 비어 있어요.")
    with open(out, "wb") as f:
        f.write(데이터)



def google_image(model, prompt, out, size, aspect):
    """Gemini 이미지 생성. 그림은 base64 로 온다."""
    열쇠 = os.environ.get("GEMINI_API_KEY", "").strip()
    if not 열쇠:
        실패("그림 만들기 열쇠가 없어요.")
    ascii확인(열쇠, "그림 만들기 열쇠")

    바탕 = os.environ.get("GEMINI_API_BASE", "https://generativelanguage.googleapis.com")
    url = 바탕.rstrip("/") + "/v1beta/interactions"
    머리 = {"x-goog-api-key": 열쇠, "Content-Type": "application/json"}
    몸통 = json.dumps({
        "model": model,
        "input": [{"type": "text", "text": prompt}],
        "response_format": {
            "type": "image",
            "mime_type": "image/jpeg",
            "aspect_ratio": aspect,
            "image_size": size,
        },
    }).encode("utf-8")

    raw = 요청(url, data=몸통, headers=머리, method="POST")
    try:
        답 = json.loads(raw.decode("utf-8"))
    except Exception:
        실패("그림을 알아볼 수 없어요.")

    b64 = _그림찾기(답)
    if not b64:
        실패("그림이 오지 않았어요.")
    try:
        데이터 = base64.b64decode(b64)
    except Exception:
        실패("그림을 알아볼 수 없어요.")
    if not 데이터:
        실패("그림이 비어 있어요.")
    with open(out, "wb") as f:
        f.write(데이터)


def _그림찾기(값):
    """output_image.data 가 정석이지만 steps 안에 들어오는 경우도 있다."""
    if isinstance(값, dict):
        oi = 값.get("output_image")
        if isinstance(oi, dict) and oi.get("data"):
            return oi["data"]
        # inlineData 형태(구형)도 받아 준다
        if 값.get("mime_type", "").startswith("image/") and 값.get("data"):
            return 값["data"]
        if 값.get("type") == "image" and 값.get("data"):
            return 값["data"]
        for v in 값.values():
            찾음 = _그림찾기(v)
            if 찾음:
                return 찾음
    if isinstance(값, list):
        for v in 값:
            찾음 = _그림찾기(v)
            if 찾음:
                return 찾음
    return None


def google_video(model, prompt, out, seconds, resolution, aspect):
    """Veo 영상 생성. 작업을 걸고 끝날 때까지 기다린 뒤 내려받는다.

    model 에 쉼표로 여러 개를 주면 앞에서부터 시도한다.

    왜 그렇게 하나 (실측, 2026-09-05 현장):
      할당량은 모델마다 따로 센다. 학생 60명이 몰리자 제일 싼
      veo-3.1-lite 만 429(RESOURCE_EXHAUSTED) 로 막혔는데, 같은 열쇠로
      veo-3.1-fast 와 veo-3.1 은 그 순간에도 멀쩡히 작업을 받았다.
      그래서 싼 것부터 걸어 보고, 막히면 다음 것으로 넘어간다.
      학생은 아무것도 눈치채지 못한다.
    """
    열쇠 = os.environ.get("GEMINI_API_KEY", "").strip()
    if not 열쇠:
        실패("영상 만들기 열쇠가 없어요.")
    ascii확인(열쇠, "영상 만들기 열쇠")

    바탕 = os.environ.get("GEMINI_API_BASE", "https://generativelanguage.googleapis.com").rstrip("/")
    머리 = {"x-goog-api-key": 열쇠, "Content-Type": "application/json"}
    몸통 = json.dumps({
        "instances": [{"prompt": prompt}],
        "parameters": {
            "durationSeconds": int(seconds),   # 문자열로 주면 400 (실측 2026-09-05)
            "resolution": resolution,
            "aspectRatio": aspect,
        },
    }).encode("utf-8")

    후보 = [m.strip() for m in str(model).split(",") if m.strip()]
    if not 후보:
        실패("영상 모델이 정해지지 않았어요.")

    raw = None
    막힌것 = []
    for i, m in enumerate(후보):
        마지막이냐 = (i == len(후보) - 1)
        try:
            raw = 요청("%s/v1beta/models/%s:predictLongRunning" % (바탕, m),
                      data=몸통, headers=머리, method="POST",
                      할당량알림=(not 마지막이냐))
            if i > 0:
                sys.stderr.write("(기록) %s 이(가) 막혀서 %s 로 만들었어요"
                                 % (",".join(막힌것), m) + chr(10))
            break
        except 할당량참:
            막힌것.append(m)     # 이 모델만 할당량이 찼다. 다음 것으로.
            continue
    if raw is None:
        실패("친구들이 한꺼번에 만들고 있어요. 조금 뒤에 다시 해 볼까요?")

    올린것 = json.loads(raw.decode("utf-8"))
    작업 = 올린것.get("name")
    if not 작업:
        실패("영상 만들기를 시작하지 못했어요.")

    간격 = float(os.environ.get("CAMP_MEDIA_POLL_SEC", "10"))
    마감 = time.time() + 20 * 60
    상태 = {}
    while time.time() < 마감:
        time.sleep(간격)
        상태 = json.loads(요청("%s/v1beta/%s" % (바탕, 작업), headers=머리).decode("utf-8"))
        if 상태.get("done"):
            break
    else:
        실패("영상 만들기가 너무 오래 걸려요.")

    if 상태.get("error"):
        실패("영상을 만들지 못했어요.")

    주소 = _url찾기(상태.get("response", 상태))
    if not 주소:
        실패("영상이 오지 않았어요.")

    # 영상 주소도 열쇠가 있어야 받을 수 있다
    데이터 = 요청(주소, headers={"x-goog-api-key": 열쇠}, timeout=300)
    if not 데이터:
        실패("영상이 비어 있어요.")
    with open(out, "wb") as f:
        f.write(데이터)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--provider", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--prompt", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--steps", type=int, default=4)
    p.add_argument("--extra", default="")
    p.add_argument("--seconds", type=int, default=5)
    p.add_argument("--size", default="1K")
    p.add_argument("--aspect", default="16:9")
    p.add_argument("--resolution", default="720p")
    p.add_argument("--kind", default="")
    a = p.parse_args()

    try:
        if a.provider == "google":
            if a.kind == "영상":
                google_video(a.model, a.prompt, a.out, a.seconds, a.resolution, a.aspect)
            else:
                google_image(a.model, a.prompt, a.out, a.size, a.aspect)
        elif a.provider == "cloudflare":
            cloudflare(a.model, a.prompt, a.out, a.steps)
        elif a.provider == "fal":
            fal(a.model, a.prompt, a.out, a.extra)
        else:
            실패("모르는 제공자예요: %s" % a.provider)
    # RuntimeError 만 잡으면 JSONDecodeError 같은 것이 트레이스백으로
    # 학생 화면에 그대로 간다(학교 프록시가 HTML 을 돌려줄 때 실제로 남).
    except Exception as e:
        # 영어 오류와 파일 경로를 학생에게 보이면 안 된다. 기록에만 남긴다.
        sys.stderr.write("(기록) %s: %s" % (type(e).__name__, e) + chr(10))
        실패("만들지 못했어요. 잠시 뒤에 다시 해 볼까요?")
    except KeyboardInterrupt:
        실패("멈췄어요.")


if __name__ == "__main__":
    main()
