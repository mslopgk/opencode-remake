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
import json
import os
import sys
import time
import urllib.error
import urllib.request

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


def 요청(url, data=None, headers=None, method=None, timeout=TIMEOUT):
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
        raise RuntimeError("서버가 거절했어요 (%s) %s" % (e.code, 본문))
    except Exception as e:
        raise RuntimeError("연결하지 못했어요: %s" % e)


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


def fal(model, prompt, out, extra):
    열쇠 = os.environ.get("FAL_KEY", "").strip()
    if not 열쇠:
        실패("영상 만들기 열쇠가 없어요.")
    ascii확인(열쇠, "영상 만들기 열쇠")

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
    raw = 요청(바탕.rstrip("/") + "/" + model, data=몸통, headers=머리, method="POST")
    올린것 = json.loads(raw.decode("utf-8"))
    상태주소 = 올린것.get("status_url")
    결과주소 = 올린것.get("response_url")
    if not 상태주소 or not 결과주소:
        실패("영상 만들기를 시작하지 못했어요.")

    # 영상은 오래 걸린다. 최대 20분까지 기다린다.
    간격 = float(os.environ.get("CAMP_MEDIA_POLL_SEC", "5"))
    마감 = time.time() + 20 * 60
    while time.time() < 마감:
        time.sleep(간격)
        상태 = json.loads(요청(상태주소, headers=머리).decode("utf-8"))
        s = 상태.get("status")
        if s == "COMPLETED":
            break
        if s in ("FAILED", "CANCELLED", "ERROR"):
            실패("영상을 만들지 못했어요.")
    else:
        실패("영상 만들기가 너무 오래 걸려요.")

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
    """Veo 영상 생성. 작업을 걸고 끝날 때까지 기다린 뒤 내려받는다."""
    열쇠 = os.environ.get("GEMINI_API_KEY", "").strip()
    if not 열쇠:
        실패("영상 만들기 열쇠가 없어요.")
    ascii확인(열쇠, "영상 만들기 열쇠")

    바탕 = os.environ.get("GEMINI_API_BASE", "https://generativelanguage.googleapis.com").rstrip("/")
    머리 = {"x-goog-api-key": 열쇠, "Content-Type": "application/json"}
    몸통 = json.dumps({
        "instances": [{"prompt": prompt}],
        "parameters": {
            "durationSeconds": str(seconds),
            "resolution": resolution,
            "aspectRatio": aspect,
        },
    }).encode("utf-8")

    raw = 요청("%s/v1beta/models/%s:predictLongRunning" % (바탕, model),
              data=몸통, headers=머리, method="POST")
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
    except RuntimeError as e:
        실패(str(e))
    except KeyboardInterrupt:
        실패("멈췄어요.")


if __name__ == "__main__":
    main()
