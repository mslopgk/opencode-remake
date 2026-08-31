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
#   그림·대표 → fal.ai (Nano Banana 2 / Google)
#       한 장 $0.08 (대표는 2K 라 $0.12).
#       원래 Cloudflare FLUX.1 schnell($0.0006)을 썼는데, 4스텝 증류
#       모델이라 프롬프트 이해력과 글자가 약했다. 캠프 결과물이
#       주최측에 보여질 물건이라 품질을 택했다.
#       Cloudflare 경로는 지우지 않고 남겨 뒀다 — 캠프 당일 fal 이
#       막히면 CAMP_MEDIA_PROVIDER=cloudflare 로 넘어갈 수 있다.
#   영상     → fal.ai (MiniMax H3) 초당 $0.08. 5초 한 편에 $0.40.
#       제한이 없으므로 여기가 유일하게 돈이 크게 나갈 수 있는 곳이다.
#       한도는 fal.ai 대시보드의 spending cap 으로 거는 것이 맞다
#       (학생을 막지 않으면서 총액만 막는다).
#   음악     → Higgsfield (seed_audio) 0.1 크레딧. 이미 사 둔 크레딧으로
#       충분하고, 무료로 음악을 만들어 주는 곳이 마땅치 않다.
#
# 사용법:
#   camp-media.sh --kind <그림|대표|음악|영상> --prompt <영어 프롬프트> \
#                 --team-dir <팀폴더> [--name <파일이름>]
#
# 성공: 저장된 파일의 팀폴더 기준 상대경로를 stdout 에 한 줄 출력
# 실패 exit 코드: 4=인자 오류, 5=생성 실패, 6=열쇠 없음
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

# 종류별 제공자·모델·확장자·대략 단가(달러).
#
# 횟수는 제한하지 않는다. 대신 **모델·해상도·영상 길이를 여기서 고정한다.**
# 학생이나 에이전트가 더 비싼 설정을 고를 수 없다.
# 값이 길이·해상도에 비례하므로 이 고정이 곧 한 장(한 편)당 상한이다.
case "$KIND" in
  그림)
    PROVIDER="fal"; MODEL="fal-ai/nano-banana-2"
    EXT="png"; STEPS=4; COST="0.080"
    EXTRA='{"num_images":1,"resolution":"1K","aspect_ratio":"16:9","output_format":"png"}' ;;
  대표)
    # 발표 표지는 프로젝터에 꽉 차게 나온다. 이 한 장만 2K 로 뽑는다.
    PROVIDER="fal"; MODEL="fal-ai/nano-banana-2"
    EXT="png"; STEPS=8; COST="0.120"
    EXTRA='{"num_images":1,"resolution":"2K","aspect_ratio":"16:9","output_format":"png"}' ;;
  음악)
    PROVIDER="higgsfield"; MODEL="seed_audio"
    EXT="wav"; STEPS=0; COST="0.000"; EXTRA='' ;;
  영상)
    PROVIDER="fal"; MODEL="minimax/h3/text-to-video"
    EXT="mp4"; STEPS=0; COST="0.400"
    EXTRA='{"duration":5}' ;;
  *) echo "만들 수 있는 것은 그림, 대표, 음악, 영상이에요." >&2; exit 4 ;;
esac

# 제공자를 갈아끼울 수 있게 한다 (시험용 + 당일 비상용).
# cloudflare 로 넘기면 FLUX.1 schnell 로 만든다. 품질은 떨어지지만 싸고,
# fal 이 막혔을 때 아무것도 못 만드는 것보다는 낫다.
PROVIDER="${CAMP_MEDIA_PROVIDER:-$PROVIDER}"
if [ "$PROVIDER" = "cloudflare" ]; then
  case "$KIND" in
    그림|대표) MODEL="@cf/black-forest-labs/flux-1-schnell"; EXTRA='' ;;
  esac
fi

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
  URL="$(higgsfield generate create "$MODEL" --prompt "$PROMPT" --wait 2>/dev/null | tail -1)"
  if [ -z "${URL:-}" ] || [ "${URL#http}" = "$URL" ]; then
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
' "$(date '+%Y-%m-%d %H:%M:%S')" "$KIND" "$COST" "$REL" >> "$USAGE_FILE"

printf '%s\n' "$REL"
