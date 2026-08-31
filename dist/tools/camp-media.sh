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
# 전부 Higgsfield 한 곳으로 모았다. 이유:
#
#   1) 한글이 된다. 여러 모델을 같은 프롬프트로 실제 생성해 비교했는데,
#      Cloudflare 계열은 "바다를 지켜요" 가 "자근 뾽난 끠나끸힐" 로 나왔다.
#      Nano Banana 2 는 정확히 썼다. 캠페인 포스터에 한글이 들어가야 하므로
#      이게 결정적이었다.
#   2) 화질이 다르다. 2048x2048 로 나온다 (Cloudflare 는 1024).
#   3) 열쇠가 필요 없다. 자격증명이 이미 설치본에 들어 있다.
#      Cloudflare·fal 로 가면 새 계정과 새 열쇠를 학생 노트북마다 심어야 한다.
#   4) 지출 상한이 구조적으로 생긴다. 횟수 제한을 없앴으므로 종량제는
#      상한이 없지만, 구독 크레딧은 다 쓰면 거기서 멈춘다.
#
# 단가 (Ultra 기준 크레딧당 약 $0.043):
#   그림 nano_banana_2_lite   1 크레딧
#   대표 nano_banana_2        2 크레딧   ← 한글 글자를 넣을 수 있다
#   음악 seed_audio         0.2 크레딧
#   영상 veo3_1_lite          8 크레딧   (5초)
#
# 비상 경로는 남겨 뒀다. Higgsfield 가 막히면 CAMP_MEDIA_PROVIDER 로
# cloudflare 나 fal 로 넘길 수 있다 (그쪽 열쇠가 있을 때만 동작한다).
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
fi

# 종류별 모델·확장자·크레딧.
#
# 횟수는 제한하지 않는다. 대신 **모델과 영상 길이를 여기서 고정한다.**
# 학생이나 에이전트가 더 비싼 모델이나 더 긴 영상을 고를 수 없다.
# 크레딧이 길이에 정확히 비례하므로(5초 8 -> 10초 16) 길이 고정이 곧
# 한 편당 상한이다. 실측으로 추정치와 실제 차감이 일치함을 확인했다.
case "$KIND" in
  그림)
    PROVIDER="higgsfield"; MODEL="nano_banana_2_lite"
    EXT="png"; STEPS=0; CREDITS="1"; EXTRA='' ;;
  대표)
    # 캠페인 포스터. 한글 글자를 정확히 써 주는 모델이라 이것만 정식판을 쓴다.
    PROVIDER="higgsfield"; MODEL="nano_banana_2"
    EXT="png"; STEPS=0; CREDITS="2"; EXTRA='' ;;
  음악)
    PROVIDER="higgsfield"; MODEL="seed_audio"
    EXT="wav"; STEPS=0; CREDITS="0.2"; EXTRA='' ;;
  영상)
    PROVIDER="higgsfield"; MODEL="veo3_1_lite"
    EXT="mp4"; STEPS=0; CREDITS="8"; EXTRA='' ;;
  *) echo "만들 수 있는 것은 그림, 대표, 음악, 영상이에요." >&2; exit 4 ;;
esac

# 제공자를 갈아끼울 수 있게 한다 (시험용 + 당일 비상용).
# 그쪽 열쇠가 media-keys.env 에 있을 때만 동작한다. 평소에는 쓰지 않는다.
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

  ERR="$(mktemp)"
  # shellcheck disable=SC2086
  URL="$(higgsfield generate create "$MODEL" --prompt "$PROMPT" $WAIT_ARGS 2>"$ERR" | tail -1)"
  MSG="$(cat "$ERR" 2>/dev/null)"
  rm -f "$ERR"

  if [ -z "${URL:-}" ] || [ "${URL#http}" = "$URL" ]; then
    # 크레딧이 바닥나는 것은 캠프 당일 실제로 일어날 수 있는 일이다.
    # "잠시 뒤에 다시" 라고 하면 학생이 계속 다시 시도한다. 구분해서 알린다.
    case "$MSG" in
      *credit*|*Credit*|*CREDIT*|*insufficient*|*balance*)
        echo "만들기 재료가 다 떨어졌어요. 선생님을 불러 주세요." >&2
        exit 7 ;;
    esac
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
  if "$PY" "$HERE/media-gen.py" --provider "$PROVIDER" --model "$MODEL" \
        --prompt "$PROMPT" --out "$DEST" --steps "$STEPS" --extra "$EXTRA" 2>"$ERR"; then
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
