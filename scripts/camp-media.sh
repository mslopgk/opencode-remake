#!/usr/bin/env bash
# 창의디자인캠프 미디어 생성 래퍼.
#
# 이 스크립트의 존재 이유: 크레딧 예산을 강제한다.
# 계정 잔액은 유한하고 15팀이 공유한다. 프롬프트로 부탁하는 것으로는
# 지켜지지 않으므로 여기서 기계적으로 막는다.
#
# 사용법:
#   camp-media.sh --kind <그림|대표|음악|영상> --prompt <영어 프롬프트> \
#                 --team-dir <팀폴더> [--name <파일이름>]
#
# 성공: 저장된 파일의 팀폴더 기준 상대경로를 stdout 에 한 줄 출력
# 실패 exit 코드: 2=영상 초과, 3=대표 초과, 4=인자 오류, 5=생성 실패
set -uo pipefail

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

# 종류별 모델·확장자·횟수 제한
case "$KIND" in
  그림)  MODEL="nano_banana_2_lite"; EXT="png"; LIMIT_KEY=""     ; LIMIT=0 ;;
  대표)  MODEL="gpt_image_2";        EXT="png"; LIMIT_KEY="대표"  ; LIMIT=2 ;;
  음악)  MODEL="seed_audio";         EXT="wav"; LIMIT_KEY=""     ; LIMIT=0 ;;
  영상)  MODEL="seedance_2_0";       EXT="mp4"; LIMIT_KEY="영상"  ; LIMIT=2 ;;
  *) echo "만들 수 있는 것은 그림, 대표, 음악, 영상이에요." >&2; exit 4 ;;
esac

COUNT_DIR="$TEAM_DIR/.camp"
COUNT_FILE="$COUNT_DIR/counts"
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

# 횟수 제한 확인 (생성 전에 막는다)
if [ -n "$LIMIT_KEY" ]; then
  USED="$(read_count "$LIMIT_KEY")"
  if [ "$USED" -ge "$LIMIT" ]; then
    if [ "$LIMIT_KEY" = "영상" ]; then
      echo "영상은 팀마다 ${LIMIT}번까지만 만들 수 있어요. 이미 ${USED}번 만들었어요." >&2
      exit 2
    else
      echo "대표 그림은 팀마다 ${LIMIT}번까지만 만들 수 있어요. 이미 ${USED}번 만들었어요." >&2
      exit 3
    fi
  fi
fi

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

# 생성
if [ "$KIND" = "영상" ]; then
  URL="$(higgsfield generate create "$MODEL" --prompt "$PROMPT" \
          --wait --wait-timeout 20m --wait-interval 5s 2>/dev/null | tail -1)"
else
  URL="$(higgsfield generate create "$MODEL" --prompt "$PROMPT" \
          --wait 2>/dev/null | tail -1)"
fi

if [ -z "${URL:-}" ] || [ "${URL#http}" = "$URL" ]; then
  echo "그림을 만들지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
  exit 5
fi

# 내려받기
if [ "${CAMP_MEDIA_FAKE_DOWNLOAD:-0}" = "1" ]; then
  printf 'fake\n' > "$DEST"
else
  if ! curl -fsSL "$URL" -o "$DEST" 2>/dev/null; then
    echo "그림을 만들지 못했어요. 잠시 뒤에 다시 해 볼까요?" >&2
    rm -f "$DEST"
    exit 5
  fi
fi

# 성공했을 때만 카운터를 올린다
if [ -n "$LIMIT_KEY" ]; then
  write_count "$LIMIT_KEY" "$(( $(read_count "$LIMIT_KEY") + 1 ))"
fi

printf '%s\n' "$REL"
