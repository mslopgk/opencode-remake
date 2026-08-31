#!/usr/bin/env bash
# 창의디자인캠프 미디어 생성 래퍼.
#
# 이 스크립트가 하는 일: 어떤 모델을 쓸지 정하고, 파일 이름을 겹치지 않게
# 붙이고, 쓴 만큼 기록을 남긴다.
#
# 횟수 제한은 없다. 주최측 결정이다 — 학생이 "다 썼어요" 벽에 막히는 것보다
# 돈을 조금 더 내는 편이 낫다. 대신 얼마나 썼는지는 기록해서 운영진이 볼 수
# 있게 한다 (<팀폴더>/.camp/usage.log).
#
# 제공자를 왜 나눴나 (실측 단가 기준):
# 전부 Google Gemini API 를 직접 쓴다. 이유:
#
#   1) 같은 모델이 가장 싸다. Nano Banana 도 Veo 도 구글이 만든 것이고,
#      제3사(fal·Higgsfield)는 여기에 마진을 얹어 되판다.
#      그림 한 장: 구글 $0.0336 / Higgsfield $0.043 / fal $0.08
#      영상 5초 : 구글 $0.25   / Higgsfield $0.34   / fal $0.40
#   2) 동시 실행 한도가 없다. 분당 요청수(RPM)와 10분당 지출로 관리한다.
#      Higgsfield 는 계정당 동시 8개라 60명이 몰리면 즉시 거절당했다
#      (20명 동시에 11/20 실패). 구글 Tier 2 는 10분당 $50 이라
#      60명이 각자 영상 3편을 동시에 만들어도 들어간다($45).
#   3) 쓴 만큼만 낸다. 구독은 적게 써도 정액이었다.
#
# 단가와 고정값:
#   그림 gemini-3.1-flash-lite-image  1K   $0.0336
#   대표 gemini-3.1-flash-image       2K   $0.101   ← 한글 글자를 정확히 쓴다
#   영상 veo-3.1-lite-generate-preview 4초 720p $0.20
#
# 음악은 뺐다. Gemini API 에 음악 생성 모델이 없고, Veo 가 영상에 소리를
# 같이 만들어 준다.
#
# 비상 경로(Higgsfield·fal·Cloudflare)는 남겨 뒀다. CAMP_MEDIA_PROVIDER 로
# 넘긴다. 그쪽 열쇠가 있을 때만 동작한다.
#
# 사용법:
#   camp-media.sh --kind <그림|대표|음악|영상> --prompt <영어 프롬프트> \
#                 --team-dir <팀폴더> [--name <파일이름>]
#
# 성공: 저장된 파일의 팀폴더 기준 상대경로를 stdout 에 한 줄 출력
# 실패 exit 코드: 4=인자 오류, 5=생성 실패, 6=열쇠 없음, 7=크레딧 소진
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND=""; PROMPT=""; TEAM_DIR=""; NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --kind)     KIND="${2:-}"; shift 2 ;;
    --prompt)   PROMPT="${2:-}"; shift 2 ;;
    --team-dir) TEAM_DIR="${2:-}"; shift 2 ;;
    --name)     NAME="${2:-}"; shift 2 ;;
    *) echo "알 수 없는 옵션이에요: $1" >&2; exit 4 ;;
  esac
done

[ -n "$KIND" ]   || { echo "무엇을 만들지 정해 주세요." >&2; exit 4; }
[ -n "$PROMPT" ] || { echo "어떤 것을 만들지 설명이 필요해요." >&2; exit 4; }
[ -n "$TEAM_DIR" ] || { echo "팀 폴더가 필요해요." >&2; exit 4; }
[ -d "$TEAM_DIR" ] || { echo "팀 폴더를 찾을 수 없어요." >&2; exit 4; }

# 열쇠는 설치할 때 심어 둔다. 학생은 입력하지 않는다.
KEYS_FILE="${CAMP_MEDIA_KEYS:-$HOME/.config/camp/media-keys.env}"
if [ -f "$KEYS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$KEYS_FILE"
  # source 만 하면 셸 변수로만 남고 자식 프로세스(python)에는 안 넘어간다.
  # 실제로 "열쇠가 없어요" 로 실패했다. 반드시 export 한다.
  for k in GEMINI_API_KEY CF_ACCOUNT_ID CF_API_TOKEN FAL_KEY; do
    eval "v=\${$k:-}"
    [ -n "$v" ] && export "$k=$v"
  done
fi

# 종류별 모델·확장자·크레딧.
#
# 횟수는 제한하지 않는다. 대신 **모델과 영상 길이를 여기서 고정한다.**
# 학생이나 에이전트가 더 비싼 모델이나 더 긴 영상을 고를 수 없다.
# 크레딧이 길이에 정확히 비례하므로(5초 8 -> 10초 16) 길이 고정이 곧
# 한 편당 상한이다. 실측으로 추정치와 실제 차감이 일치함을 확인했다.
case "$KIND" in
  그림)
    PROVIDER="google"; MODEL="gemini-3.1-flash-lite-image"
    EXT="jpg"; SIZE="1K"; ASPECT="16:9"; SECS=0; RES=""
    CREDITS="0.0336"; EXTRA='' ;;
  대표)
    # 캠페인 포스터. 한글을 정확히 쓰는 모델이고 이 한 장만 2K 로 뽑는다.
    PROVIDER="google"; MODEL="gemini-3.1-flash-image"
    EXT="jpg"; SIZE="2K"; ASPECT="16:9"; SECS=0; RES=""
    CREDITS="0.101"; EXTRA='' ;;
  영상)
    PROVIDER="google"; MODEL="veo-3.1-lite-generate-preview"
    EXT="mp4"; SIZE=""; ASPECT="16:9"; SECS=4; RES="720p"
    CREDITS="0.200"; EXTRA='' ;;
  *) echo "만들 수 있는 것은 그림, 대표, 영상이에요." >&2; exit 4 ;;
esac

# 제공자를 갈아끼울 수 있게 한다 (시험용 + 당일 비상용).
# 그쪽 열쇠가 media-keys.env 에 있을 때만 동작한다. 평소에는 쓰지 않는다.
# 비상 경로는 이 값들을 안 정할 수 있으니 기본값을 채운다
STEPS="${STEPS:-4}"; SIZE="${SIZE:-1K}"; ASPECT="${ASPECT:-16:9}"
RES="${RES:-720p}"; SECS="${SECS:-4}"
PROVIDER="${CAMP_MEDIA_PROVIDER:-$PROVIDER}"
case "$PROVIDER" in
  cloudflare)
    case "$KIND" in
      그림|대표) MODEL="@cf/black-forest-labs/flux-1-schnell"; STEPS=4; EXTRA='' ;;
    esac ;;
  fal)
    case "$KIND" in
      그림|대표) MODEL="fal-ai/nano-banana-2"
        EXTRA='{"num_images":1,"resolution":"1K","aspect_ratio":"16:9","output_format":"png"}' ;;
      영상) MODEL="minimax/h3/text-to-video"; EXTRA='{"duration":5}' ;;
    esac ;;
esac

COUNT_DIR="$TEAM_DIR/.camp"
COUNT_FILE="$COUNT_DIR/counts"
USAGE_FILE="$COUNT_DIR/usage.log"
mkdir -p "$COUNT_DIR" "$TEAM_DIR/assets"
[ -f "$COUNT_FILE" ] || : > "$COUNT_FILE"

read_count() {
  local key="$1" v
  v="$(grep "^${key}=" "$COUNT_FILE" 2>/dev/null | tail -1 | cut -d= -f2)"
  echo "${v:-0}"
}

write_count() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  grep -v "^${key}=" "$COUNT_FILE" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$COUNT_FILE"
}

# 파일 이름 결정 (겹치지 않게 번호를 붙인다)
if [ -z "$NAME" ]; then
  case "$KIND" in
    그림) BASE="그림" ;;
    대표) BASE="포스터" ;;
    음악) BASE="음악" ;;
    영상) BASE="영상" ;;
  esac
  n=1
  while [ -e "$TEAM_DIR/assets/${BASE}-${n}.${EXT}" ]; do n=$((n+1)); done
  NAME="${BASE}-${n}.${EXT}"
fi
case "$NAME" in *.*) ;; *) NAME="${NAME}.${EXT}" ;; esac
REL="assets/$NAME"
DEST="$TEAM_DIR/$REL"

# ── 만들기 ──────────────────────────────────────────────────────
if [ "${CAMP_MEDIA_FAKE_DOWNLOAD:-0}" = "1" ]; then
  # 시험용. 실제로 부르지 않고 파일만 만든다.
  printf 'fake\n' > "$DEST"
elif [ "$PROVIDER" = "higgsfield" ]; then
  # 영상은 1~2분 걸린다. 그림은 몇 초다. 기다리는 시간을 종류에 맞춘다.
  if [ "$KIND" = "영상" ]; then
    WAIT_ARGS="--wait --wait-timeout 12m --wait-interval 10s"
  else
    WAIT_ARGS="--wait"
  fi

  # 동시 실행 한도에 걸리면 여기서 스스로 다시 해 본다.
  #
  # 실측: Plus 플랜은 concurrent_jobs_limit 이 8 이고, 넘으면 큐에 넣지 않고
  # 즉시 거절한다(11초 만에 실패). 60명이 한 계정을 쓰므로 선생님이
  # "이제 그림 만들어 보세요" 라고 말하는 순간 무더기로 걸린다.
  # 거절은 크레딧을 먹지 않고 슬롯은 20초 안에 빈다. 학생에게 오류를
  # 보여 주고 다시 누르게 하는 것보다 여기서 기다렸다 다시 하는 게 낫다.
  # 60명이 한꺼번에 몰리는 최악의 경우까지 버티게 잡는다.
  # 한도 8, 그림 한 장 22초면 60명이 빠지는 데 약 165초 걸린다.
  # 12번 × (실패감지 11초 + 최대 20초 대기) ≈ 6분까지 버틴다.
  ATTEMPT=0
  MAX_ATTEMPT="${CAMP_MEDIA_RETRIES:-12}"
  URL=""
  while [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    ERR="$(mktemp)"
    # shellcheck disable=SC2086
    URL="$(higgsfield generate create "$MODEL" --prompt "$PROMPT" $WAIT_ARGS 2>"$ERR" | tail -1)"
    MSG="$(cat "$ERR" 2>/dev/null)"
    rm -f "$ERR"

    if [ -n "${URL:-}" ] && [ "${URL#http}" != "$URL" ]; then
      break
    fi

    # 크레딧이 바닥난 것은 기다려도 안 된다. 바로 알린다.
    case "$MSG" in
      *credit*|*Credit*|*CREDIT*|*insufficient*|*balance*)
        echo "만들기 재료가 다 떨어졌어요. 선생님을 불러 주세요." >&2
        exit 7 ;;
    esac

    # 동시 한도면 잠깐 기다렸다 다시 한다.
    # 여러 명이 동시에 걸리므로 같은 시각에 몰려 재시도하지 않도록 흔든다.
    case "$MSG" in
      *rate_limit*|*concurrent*|*429*|*too\ many*|*Too\ Many*)
        if [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; then
          # 대기는 20초에서 멈춘다. 계속 늘리면 마지막 학생이 너무 오래 기다린다.
          BACKOFF=$(( ATTEMPT * 5 ))
          [ "$BACKOFF" -gt 20 ] && BACKOFF=20
          sleep "$(( BACKOFF + (RANDOM % 6) ))"
          URL=""
          continue
        fi ;;
    esac

    URL=""
    break
  done

  if [ -z "${URL:-}" ]; then
    echo "만들지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
    exit 5
  fi
  if ! curl -fsSL "$URL" -o "$DEST" 2>/dev/null; then
    echo "만들지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
    rm -f "$DEST"
    exit 5
  fi
else
  # Windows 에는 실행하면 "Microsoft Store 에서 설치하라" 고만 하는 가짜
  # python3 가 PATH 에 있다(실측). 이름만 보지 말고 실제로 되는지 확인한다.
  PY=""
  for c in python py python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then
      PY="$c"; break
    fi
  done
  if [ -z "$PY" ]; then
    echo "만들기 도구가 없어요. 선생님을 불러 주세요." >&2
    exit 5
  fi
  ERR="$(mktemp)"
  # 파이썬이 한국어 메시지를 cp949 로 쓰면 아래 case 패턴이 안 맞는다(실측).
  # media-gen.py 안에서도 고정하지만 여기서도 한 번 더 못박는다.
  export PYTHONIOENCODING=utf-8
  if "$PY" "$HERE/media-gen.py" --provider "$PROVIDER" --model "$MODEL" \
        --prompt "$PROMPT" --out "$DEST" --kind "$KIND" \
        --steps "$STEPS" --extra "$EXTRA" \
        --seconds "$SECS" --size "$SIZE" \
        --aspect "$ASPECT" --resolution "$RES" 2>"$ERR"; then
    rm -f "$ERR"
  else
    MSG="$(tail -1 "$ERR" 2>/dev/null)"
    rm -f "$ERR" "$DEST"
    case "$MSG" in
      *열쇠가\ 없어요*) echo "${MSG}" >&2; exit 6 ;;
      *) echo "${MSG:-만들지 못했어요. 잠시 뒤에 다시 해 볼까요?}" >&2; exit 5 ;;
    esac
  fi
fi

# 파일이 실제로 생겼는지 본다
if [ ! -s "$DEST" ]; then
  rm -f "$DEST"
  echo "만들지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
  exit 5
fi

# 성공했을 때만 기록한다. 막지는 않지만, 얼마나 썼는지는 남긴다.
write_count "$KIND" "$(( $(read_count "$KIND") + 1 ))"
printf '%s	%s	%s	%s
' "$(date '+%Y-%m-%d %H:%M:%S')" "$KIND" "$CREDITS" "$REL" >> "$USAGE_FILE"

printf '%s\n' "$REL"
