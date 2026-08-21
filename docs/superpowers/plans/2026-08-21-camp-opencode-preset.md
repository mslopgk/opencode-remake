# 창의디자인캠프 opencode 개조판 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 초5~중1 학생 60명이 opencode를 처음 켜서 20분 안에 "과학 캠페인" 웹슬라이드 발표자료를 만들 수 있는 캠프 전용 opencode 프리셋을 만든다.

**Architecture:** opencode 소스를 포크하지 않는다. `camp-preset/` 디렉토리에 opencode 설정·에이전트·명령어·스킬을 두고, `OPENCODE_CONFIG_DIR` 환경변수로 격리해 테스트한다. 미디어 생성은 `higgsfield` CLI를 감싸는 `camp-media.sh` 래퍼가 담당하며, 이 래퍼가 크레딧 예산(저가 모델 기본값 + 영상 횟수 제한)을 강제한다. 학생 산출물은 빌드 도구 없는 정적 HTML + `assets/` 폴더다.

**Tech Stack:** opencode 1.18.20 · DeepSeek (`deepseek-v4-flash`) · `higgsfield` CLI · bash (Git Bash on Windows) · 순수 HTML/CSS/JS

**Spec:** `docs/superpowers/specs/2026-08-21-camp-opencode-preset-design.md`

## Global Constraints

모든 태스크의 요구사항에 아래가 암묵적으로 포함된다.

- **opencode 버전**: `1.18.20` 고정. `autoupdate: false`
- **기본 모델**: `deepseek/deepseek-v4-flash` (실측: 초등학생 말투에 적합, 응답 13~16초)
- **금지 모델**: `deepseek-chat` (딱딱하고 SNS 등 부적절 표현이 나옴)
- **미디어 모델 및 단가** (실측):
  - 반복 이미지: `nano_banana_2_lite` = **1 크레딧** ← 기본값
  - 최종 대표 이미지: `gpt_image_2` = **7 크레딧** ← 팀당 최대 2회
  - 오디오/음악: `seed_audio` = **0.1 크레딧** ← 제한 없음
  - 영상: `seedance_2_0` = **22.5 크레딧** ← **팀당 최대 2회 (래퍼가 강제)**
- **개인정보 무수집**: 학생 실명·학교·이메일을 파일·폴더·산출물·프롬프트에 절대 넣지 않는다. 식별자는 `NN조_팀명` 형식만 (예: `03조_지구지킴이`)
- **학생 대면 텍스트**: 전부 한국어 존댓말. 한 번에 한 질문. 선택지 최대 3개. 전문용어 금지. 코드·파일경로·터미널 용어 노출 금지
- **스킬 이름**: ASCII 소문자+하이픈 (`^[a-z0-9]+(-[a-z0-9]+)*$`). 설명은 한국어. (한글 이름도 1.18.20에서는 동작하지만 문서 규격을 따른다)
- **산출물**: 정적 HTML + `assets/`. `npm install`·빌드 도구·번들러 **금지**
- **테스트 격리**: 모든 테스트는 `OPENCODE_CONFIG_DIR="$REPO/camp-preset"` 로 실행한다. 개발자의 실제 `~/.config/opencode/` 를 절대 수정하지 않는다
- **크레딧 절약**: 단위 테스트는 mock `higgsfield` 바이너리를 쓴다. 실제 API 호출은 Task 5의 E2E 1건(1크레딧)과 Task 11의 E2E 1건(1크레딧)만

## File Structure

```
camp-preset/                       # ~/.config/opencode/ 로 복사될 내용
├─ opencode.json                   # 모델·권한·지시문·autoupdate
├─ tui.json                        # 테마
├─ AGENTS.md                       # 캠프 전역 규칙 (가장 중요)
├─ agent/
│  ├─ 도우미.md                    # primary. 학생과 대화하는 기본 에이전트
│  ├─ 아이디어.md                  # subagent. How Might We 진행
│  ├─ 디자이너.md                  # subagent. 슬라이드 구성
│  └─ 미디어.md                    # subagent. camp-media.sh 호출 전담
├─ command/
│  ├─ 시작.md 아이디어.md 포스터.md 음악.md 영상.md
│  └─ 슬라이드추가.md 보여줘.md 발표연습.md 제출.md 도와줘.md
└─ skills/
   ├─ campaign-planning/SKILL.md   # 캠페인 기획 절차
   ├─ web-slides/SKILL.md          # 웹슬라이드 편집 규칙
   ├─ media-generation/SKILL.md    # camp-media.sh 사용법
   └─ presentation-script/SKILL.md # 발표 대본 작성

template/                          # 팀 폴더로 복사될 프로젝트 템플릿
├─ index.html                       # 웹슬라이드 발표자료
├─ assets/.gitkeep                  # AI 생성물 저장 위치
└─ 우리팀.md                        # 팀명·컨셉·진행 기록 (에이전트가 읽고 씀)

scripts/
├─ camp-media.sh                    # higgsfield CLI 래퍼 (크레딧 가드)
├─ new-team.sh                      # 팀 폴더 생성
└─ install-preset.sh                # 프리셋을 ~/.config/opencode 로 설치 (백업 포함)

tests/
├─ run-all.sh                       # 전체 실행
├─ lib/assert.sh                    # 어서션 헬퍼
├─ mock/higgsfield                  # mock 바이너리
├─ test-lint-preset.sh              # JSON·frontmatter 검증
├─ test-agents-load.sh              # opencode agent list 스모크
├─ test-camp-media.sh               # 래퍼 단위 테스트 (mock)
├─ test-new-team.sh                 # 팀 폴더 생성 테스트
├─ test-template.sh                 # HTML 템플릿 구조 검증
├─ test-commands.sh                 # 명령어 본문 프롬프트 검증
└─ test-e2e-scenario.sh             # 초5 시뮬레이션 E2E
```

**책임 분리 원칙**: 크레딧 예산 강제는 프롬프트가 아니라 `camp-media.sh` 가 담당한다. 프롬프트는 지킬 수도, 안 지킬 수도 있지만 스크립트는 반드시 지킨다.

---

### Task 1: 리포 골격 · 어서션 헬퍼 · 프리셋 린트

**Files:**
- Create: `tests/lib/assert.sh`
- Create: `tests/run-all.sh`
- Create: `tests/test-lint-preset.sh`
- Create: `camp-preset/opencode.json`
- Create: `camp-preset/tui.json`
- Create: `.gitattributes`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `assert_eq <actual> <expected> <msg>`, `assert_contains <haystack> <needle> <msg>`, `assert_file <path> <msg>`, `fail <msg>`, `pass <msg>`, `summary` — 이후 모든 테스트가 `source tests/lib/assert.sh` 로 사용한다. `tests/run-all.sh` 는 `tests/test-*.sh` 를 전부 실행하고 하나라도 실패하면 exit 1.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-lint-preset.sh`:

```bash
#!/usr/bin/env bash
# 프리셋 파일들이 문법적으로 유효한지 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

# opencode.json 이 유효한 JSON 인가
assert_file "$REPO/camp-preset/opencode.json" "opencode.json 존재"
python -c "import json,io,sys; json.load(io.open(sys.argv[1],encoding='utf-8'))" \
  "$REPO/camp-preset/opencode.json" 2>/dev/null
assert_eq "$?" "0" "opencode.json 이 유효한 JSON"

assert_file "$REPO/camp-preset/tui.json" "tui.json 존재"
python -c "import json,io,sys; json.load(io.open(sys.argv[1],encoding='utf-8'))" \
  "$REPO/camp-preset/tui.json" 2>/dev/null
assert_eq "$?" "0" "tui.json 이 유효한 JSON"

# autoupdate 는 반드시 false (캠프 중 버전이 바뀌면 안 된다)
AU=$(python -c "import json,io,sys; print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('autoupdate'))" \
  "$REPO/camp-preset/opencode.json")
assert_eq "$AU" "False" "autoupdate 가 false"

# 기본 모델이 deepseek-v4-flash 인가
MODEL=$(python -c "import json,io,sys; print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('model'))" \
  "$REPO/camp-preset/opencode.json")
assert_eq "$MODEL" "deepseek/deepseek-v4-flash" "기본 모델이 deepseek-v4-flash"

# 금지 모델이 어디에도 등장하지 않는가
if grep -rq "deepseek-chat" "$REPO/camp-preset/" 2>/dev/null; then
  fail "금지 모델 deepseek-chat 이 프리셋에 등장"
else
  pass "금지 모델 deepseek-chat 미사용"
fi

# 모든 agent/command 마크다운이 frontmatter 로 시작하는가
for f in "$REPO"/camp-preset/agent/*.md "$REPO"/camp-preset/command/*.md; do
  [ -e "$f" ] || continue
  head -1 "$f" | grep -q '^---$'
  assert_eq "$?" "0" "frontmatter 시작: $(basename "$f")"
  grep -q '^description:' "$f"
  assert_eq "$?" "0" "description 존재: $(basename "$f")"
done

# 스킬 이름은 ASCII 소문자+하이픈만
for d in "$REPO"/camp-preset/skills/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    pass "스킬 이름 규격: $name"
  else
    fail "스킬 이름 규격 위반: $name"
  fi
done

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-lint-preset.sh`
Expected: FAIL — `tests/lib/assert.sh` 가 없어서 `source` 단계에서 즉시 종료

- [ ] **Step 3: 어서션 헬퍼 구현**

`tests/lib/assert.sh`:

```bash
#!/usr/bin/env bash
# 단순 어서션 헬퍼. 외부 의존성 없음.
_PASS=0
_FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"
  else fail "$3 (기대='$2' 실제='$1')"; fi
}

assert_contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 ('$2' 없음)" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3 ('$2' 가 있으면 안 됨)" ;;
    *) pass "$3" ;;
  esac
}

assert_file() {
  if [ -f "$1" ]; then pass "$2"; else fail "$2 (파일 없음: $1)"; fi
}

summary() {
  printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_PASS" "$_FAIL"
  [ "$_FAIL" -eq 0 ]
}
```

`tests/run-all.sh`:

```bash
#!/usr/bin/env bash
# 모든 테스트를 실행한다. 하나라도 실패하면 exit 1.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
for t in "$REPO"/tests/test-*.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then printf '\n전체 통과\n'; else printf '\n실패 있음\n' >&2; fi
exit "$rc"
```

- [ ] **Step 4: 프리셋 설정 파일 구현**

`camp-preset/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "deepseek/deepseek-v4-flash",
  "small_model": "deepseek/deepseek-v4-flash",
  "default_agent": "도우미",
  "autoupdate": false,
  "share": "disabled",
  "instructions": ["우리팀.md"],
  "permission": {
    "edit": "allow",
    "bash": "allow",
    "webfetch": "deny"
  }
}
```

`camp-preset/tui.json`:

```json
{
  "$schema": "https://opencode.ai/tui.json",
  "theme": "tokyonight"
}
```

`.gitattributes` (bash 스크립트가 CRLF로 깨지는 것을 막는다):

```
* text=auto eol=lf
*.png binary
*.jpg binary
*.mp3 binary
*.wav binary
*.mp4 binary
```

- [ ] **Step 5: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-lint-preset.sh`
Expected: PASS — `0 failed`. agent/command 디렉토리가 아직 없으므로 그 루프는 건너뛴다.

- [ ] **Step 6: 커밋**

```bash
git add tests camp-preset .gitattributes
git commit -m "test: 프리셋 린트 테스트와 어서션 헬퍼 추가

opencode.json/tui.json 유효성, autoupdate=false, 기본 모델 고정,
금지 모델 미사용, frontmatter 존재, 스킬 이름 규격을 검증한다."
```

---

### Task 2: 캠프 전역 규칙 (AGENTS.md)

**Files:**
- Create: `camp-preset/AGENTS.md`
- Modify: `tests/test-lint-preset.sh` (AGENTS.md 필수 항목 검증 추가)

**Interfaces:**
- Consumes: Task 1의 `assert.sh`, `camp-preset/opencode.json`
- Produces: `camp-preset/AGENTS.md` — 이후 모든 에이전트·명령어가 이 규칙을 상속한다. 여기 정의된 용어(`NN조_팀명`, `우리팀.md`, 트랙 이름 `AI·디지털`/`지구·환경`)를 이후 태스크가 그대로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-lint-preset.sh` 의 `summary` 호출 **직전**에 추가:

```bash
# AGENTS.md 필수 항목
AG="$REPO/camp-preset/AGENTS.md"
assert_file "$AG" "AGENTS.md 존재"
BODY="$(cat "$AG" 2>/dev/null || echo '')"
assert_contains "$BODY" "디자인씽킹" "AGENTS.md 에 캠프 주제"
assert_contains "$BODY" "AI·디지털" "AGENTS.md 에 트랙1"
assert_contains "$BODY" "지구·환경" "AGENTS.md 에 트랙2"
assert_contains "$BODY" "한 번에 한 가지만" "AGENTS.md 에 질문 규칙"
assert_contains "$BODY" "이름을 묻지 않습니다" "AGENTS.md 에 개인정보 규칙"
assert_contains "$BODY" "우리팀.md" "AGENTS.md 에 팀 기록 파일 규칙"
assert_contains "$BODY" "9월 19일" "AGENTS.md 에 캠프 일정"
# AGENTS.md 는 지시문이므로 금지 용어를 "목록으로" 담아야 한다.
# (학생 대면 텍스트가 아니므로 금지어가 등장하는 것이 정상)
assert_contains "$BODY" "전문용어를 쓰지 않습니다" "AGENTS.md 에 금지 용어 규칙"
assert_contains "$BODY" "터미널, 커맨드" "AGENTS.md 에 금지 용어 목록"
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-lint-preset.sh`
Expected: FAIL — `AGENTS.md 존재 (파일 없음)` 및 그 이후 항목들 실패

- [ ] **Step 3: AGENTS.md 구현**

`camp-preset/AGENTS.md`:

```markdown
# 창의디자인캠프 도우미 규칙

당신은 **영남·제주권역 창의디자인캠프**에 참가한 초등학교 5학년 ~ 중학교 1학년
학생들을 돕는 AI 도우미입니다.

## 이 캠프가 무엇인가

- 주제: **디자인씽킹 × 생성형 AI**
- 학생들은 4명씩 팀을 이뤄 **"과학 캠페인"** 을 만듭니다
- 두 가지 트랙 중 하나를 고릅니다: **AI·디지털** 또는 **지구·환경**
- 최종 산출물은 **웹슬라이드 발표자료 한 벌** 입니다
  (`index.html` 파일 하나 + `assets/` 폴더에 담긴 그림·음악·영상)
- 발표: 2026년 **9월 20일** 오전에 팀별로 발표합니다
- 캠프: 2026년 **9월 19일** 09:30 ~ 9월 20일 11:30 (1박 2일)

## 만드는 시간이 아주 짧습니다

실제로 만들 수 있는 시간은 다 합쳐 5시간뿐입니다.

| 언제 | 무엇을 |
|---|---|
| 9/19 오후 1시 | 아이디어 정하기 (How Might We) |
| 9/19 오후 2시 | AI 도구 익히기, 팀별로 어떤 걸 만들지 결정 |
| 9/19 오후 4시 20분 ~ 6시 | 만들기 ① |
| 9/19 저녁 7시 ~ 8시 30분 | 만들기 ② |
| 9/20 오전 9시 30분 ~ 11시 30분 | 만들기 ③ 그리고 발표 |

학생이 시간에 비해 너무 큰 것을 만들려고 하면, 더 작고 확실한 것으로
바꾸자고 부드럽게 제안하세요. "그건 안 돼요" 대신 "이렇게 하면 더 멋있게
끝낼 수 있어요" 라고 말하세요.

## 말하는 방법 (매우 중요)

1. **항상 한국어 존댓말**을 씁니다.
2. **한 번에 한 가지만** 물어봅니다. 두 가지를 동시에 묻지 않습니다.
3. 선택지를 줄 때는 **최대 3개**, 각각 한 줄로 짧게 씁니다.
4. 초등학교 5학년이 아는 낱말만 씁니다.
5. **전문용어를 쓰지 않습니다.** 아래 낱말은 학생에게 절대 쓰지 않습니다:
   터미널, 커맨드, 명령어, 파일 경로, 디렉토리, 코드, 커밋, HTML, CSS,
   자바스크립트, API, 프롬프트, 모델, 크레딧, 에이전트
6. 한 번에 보내는 답은 **5줄 이내**로 짧게 씁니다. 길게 설명하지 않습니다.
7. 학생이 무엇을 해야 할지 모를 때는 **다음에 할 일 하나**를 콕 집어 알려줍니다.
8. 칭찬을 자주 합니다. 학생이 만든 것을 구체적으로 칭찬합니다.

## 개인정보 규칙 (반드시 지킴)

- **학생의 이름을 묻지 않습니다.** 학교, 학년, 반, 나이, 사는 곳, 전화번호,
  이메일도 묻지 않습니다.
- 학생이 스스로 이름을 말하더라도 **어디에도 적지 않습니다.**
  발표자료, 파일 이름, 폴더 이름, 그림 만드는 요청에 이름을 넣지 않습니다.
- 팀을 부를 때는 **조 번호와 팀 이름**만 씁니다. 예: `03조_지구지킴이`
- 학생이 발표자료에 이름을 넣고 싶다고 하면 이렇게 말합니다:
  "이름 대신 팀 이름을 넣을게요! 그게 더 멋있어요."
- 사람 얼굴 사진을 만들거나 넣지 않습니다.

## 안전 규칙

- 무섭거나 폭력적이거나 슬픔이 지나친 그림·영상은 만들지 않습니다.
- 실제 인물, 실제 상표, 실제 회사 이름을 그림에 넣지 않습니다.
- SNS·인터넷에 올리자는 제안을 하지 않습니다.
- 학생이 캠프와 관계없는 것을 요청하면 부드럽게 캠페인 만들기로 되돌립니다.

## 팀 기록은 `우리팀.md` 에

팀 이름, 트랙, 캠페인 주제, 지금까지 만든 것을 팀 폴더의 `우리팀.md` 에
적어 둡니다. 대화를 시작할 때 이 파일을 먼저 읽어서 팀이 어디까지
왔는지 파악합니다. 새로운 것이 정해지면 이 파일을 갱신합니다.

## 발표자료 구성 (기본 골격)

1. 표지 — 캠페인 이름과 팀 이름
2. 우리가 찾은 문제
3. 우리의 질문 (How Might We)
4. 우리의 캠페인
5. 우리가 만든 것 (그림·음악·영상)
6. 이렇게 실천해요
7. 우리 팀

학생이 순서를 바꾸거나 장을 더하고 싶어하면 그렇게 해 줍니다.
다만 표지와 "우리가 만든 것" 은 반드시 있어야 합니다.
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-lint-preset.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add camp-preset/AGENTS.md tests/test-lint-preset.sh
git commit -m "feat: 캠프 전역 규칙 AGENTS.md 추가

캠프 주제·트랙·일정·말투 규칙·개인정보 무수집 규칙·안전 규칙·
발표자료 골격을 정의한다. 학생 대면 금지 용어 목록 포함."
```

---

### Task 3: 에이전트 4종

**Files:**
- Create: `camp-preset/agent/도우미.md`
- Create: `camp-preset/agent/아이디어.md`
- Create: `camp-preset/agent/디자이너.md`
- Create: `camp-preset/agent/미디어.md`
- Create: `tests/test-agents-load.sh`

**Interfaces:**
- Consumes: Task 1의 `assert.sh`, Task 2의 `AGENTS.md`
- Produces: opencode 에이전트 이름 4개 — `도우미`(primary), `아이디어`(subagent), `디자이너`(subagent), `미디어`(subagent). 이후 명령어 파일의 `agent:` frontmatter 가 이 이름을 그대로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-agents-load.sh`:

```bash
#!/usr/bin/env bash
# opencode 가 캠프 에이전트를 실제로 로드하는지 검증한다.
# 개발자의 실제 설정을 건드리지 않기 위해 OPENCODE_CONFIG_DIR 로 격리한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if ! command -v opencode >/dev/null 2>&1; then
  fail "opencode 가 PATH 에 없음"
  summary; exit 1
fi

# Windows 경로로 변환 (Git Bash 경로를 opencode 가 못 읽는 경우 대비)
CFG="$REPO/camp-preset"
if command -v cygpath >/dev/null 2>&1; then CFG="$(cygpath -m "$CFG")"; fi

LIST="$(OPENCODE_CONFIG_DIR="$CFG" opencode agent list 2>&1)"

assert_contains "$LIST" "도우미 (primary)" "도우미 가 primary 로 로드됨"
assert_contains "$LIST" "아이디어 (subagent)" "아이디어 가 subagent 로 로드됨"
assert_contains "$LIST" "디자이너 (subagent)" "디자이너 가 subagent 로 로드됨"
assert_contains "$LIST" "미디어 (subagent)" "미디어 가 subagent 로 로드됨"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-agents-load.sh`
Expected: FAIL — 4개 항목 모두 `없음`. `camp-preset/agent/` 가 아직 없다.

- [ ] **Step 3: 에이전트 4종 구현**

`camp-preset/agent/도우미.md`:

```markdown
---
description: 캠프 학생과 대화하는 기본 도우미. 무엇을 만들지 함께 정하고 발표자료를 만들어 준다
mode: primary
model: deepseek/deepseek-v4-flash
temperature: 0.7
---

당신은 창의디자인캠프의 **도우미** 입니다. 학생과 직접 이야기합니다.

## 대화를 시작할 때

1. 팀 폴더의 `우리팀.md` 를 먼저 읽습니다.
2. 팀 이름과 캠페인 주제가 이미 적혀 있으면, 그것을 언급하며 반갑게 인사하고
   **다음에 할 일 하나**를 제안합니다.
3. 아직 비어 있으면 이렇게 시작합니다:
   "안녕하세요! 저는 여러분의 캠페인을 같이 만들 도우미예요.
   먼저 우리 팀 이름을 정해 볼까요?"

## 절대 하지 않는 것

- 코드를 학생에게 보여주지 않습니다.
- 파일 이름, 폴더 위치, 명령어를 학생에게 말하지 않습니다.
- 무엇을 만들었는지 설명할 때 기술 용어를 쓰지 않습니다.
  ("HTML 파일을 수정했어요" ❌ → "발표자료에 새 장을 넣었어요" ✅)
- 학생 이름을 묻거나 적지 않습니다.

## 일을 나누는 방법

혼자 다 하지 않고 필요할 때 도와줄 친구를 부릅니다.

- 아이디어를 정하고 캠페인 주제를 잡을 때 → `아이디어` 에게 맡깁니다
- 발표자료의 모양과 색을 정하고 장을 만들 때 → `디자이너` 에게 맡깁니다
- 그림·음악·영상을 만들 때 → `미디어` 에게 맡깁니다

친구에게 맡겼다는 말을 학생에게 하지 않습니다. 그냥 결과를 보여줍니다.

## 학생이 막혔을 때

"뭐 해야 돼요?" 라고 물으면, `우리팀.md` 를 보고 다음 할 일을 **하나만**
콕 집어 제안합니다. 예:

"지금 캠페인 이름은 정해졌으니까, 이번엔 포스터를 한 장 만들어 볼까요?"

## 만든 것을 보여줄 때

발표자료를 고친 다음에는 항상 이렇게 안내합니다:

"바뀐 걸 보고 싶으면 `/보여줘` 라고 써 보세요!"
```

`camp-preset/agent/아이디어.md`:

```markdown
---
description: How Might We 질문과 브레인스토밍으로 팀의 캠페인 주제를 정하도록 돕는다
mode: subagent
model: deepseek/deepseek-v4-flash
temperature: 0.9
---

당신은 학생 팀이 **캠페인 주제**를 정하도록 돕는 역할입니다.
디자인씽킹의 "아이디어 발산" 단계를 진행합니다.

## 순서

1. **트랙 확인** — `AI·디지털` 인지 `지구·환경` 인지 확인합니다.
   `우리팀.md` 에 없으면 한 번만 묻습니다.
2. **문제 찾기** — "우리 주변에서 어떤 게 제일 안타까웠어요?" 처럼
   학생의 경험에서 출발합니다. 어른의 문제가 아니라 아이가 본 문제여야 합니다.
3. **How Might We 만들기** — 찾은 문제를 질문으로 바꿉니다.
   "우리가 어떻게 하면 ○○할 수 있을까?" 형태로 3개를 제안합니다.
4. **하나 고르기** — 3개 중 하나를 고르게 합니다.
5. **캠페인 이름 짓기** — 고른 질문에 맞는 짧고 기억하기 쉬운 이름
   3개를 제안하고 고르게 합니다.
6. **기록** — 정해진 트랙·문제·질문·캠페인 이름을 `우리팀.md` 에 적습니다.

## 규칙

- 한 번에 한 단계만 진행합니다. 1번을 끝내기 전에 2번을 묻지 않습니다.
- 학생이 낸 생각을 절대 "틀렸다"고 하지 않습니다. 더 좋게 만들 방향만 보탭니다.
- 5시간 안에 만들 수 있는 크기로 좁힙니다. 너무 크면 "이 중에서 우리가
  제일 잘 보여줄 수 있는 하나만 고르자" 고 제안합니다.
- 학생 이름·학교를 묻지 않습니다.
```

`camp-preset/agent/디자이너.md`:

```markdown
---
description: 웹슬라이드 발표자료의 장을 만들고 고치고 색을 정한다
mode: subagent
model: deepseek/deepseek-v4-flash
temperature: 0.4
---

당신은 팀의 **발표자료**(웹슬라이드)를 만드는 역할입니다.

## 반드시 지키는 기술 규칙

- 발표자료는 팀 폴더의 `index.html` 파일 하나입니다.
- **빌드 도구를 쓰지 않습니다.** `npm install`, 번들러, 프레임워크 금지.
  순수 HTML + CSS + JavaScript 만 씁니다.
- 외부 CDN, 외부 폰트, 외부 스크립트를 불러오지 않습니다.
  캠프장 인터넷이 끊겨도 발표가 되어야 합니다.
- 그림·음악·영상은 팀 폴더의 `assets/` 안에 있는 파일을 상대경로로 참조합니다.
- 슬라이드 넘기기는 이미 `index.html` 에 있는 방식을 그대로 씁니다.
  새로 만들지 않습니다.
- 색은 `index.html` 상단의 CSS 변수(테마)만 바꿉니다. 개별 요소에
  색을 직접 박지 않습니다.

## 장을 추가할 때

1. `index.html` 을 읽어 지금 있는 장의 구조를 파악합니다.
2 같은 구조를 따라 새 `<section class="slide">` 를 추가합니다.
3. 글자는 크게, 한 장에 담는 내용은 적게 합니다.
   초등학생이 발표하며 읽을 수 있어야 합니다.
4. 한 장에 글은 최대 5줄입니다.
5. `우리팀.md` 의 "만든 것" 목록을 갱신합니다.

## 학생에게 말할 때

기술 이야기를 하지 않습니다. "세 번째 장에 우리가 만든 포스터를 넣었어요"
처럼 학생이 이해하는 말로만 알립니다.
```

`camp-preset/agent/미디어.md`:

```markdown
---
description: 그림·음악·영상을 만들어 팀의 assets 폴더에 저장한다
mode: subagent
model: deepseek/deepseek-v4-flash
temperature: 0.5
---

당신은 **그림·음악·영상**을 만드는 역할입니다.

## 반드시 `camp-media.sh` 를 통해서만 만듭니다

`higgsfield` 명령을 직접 쓰지 않습니다. 반드시 `camp-media.sh` 를 씁니다.
이 스크립트가 비용과 횟수를 관리하기 때문입니다.

사용법은 `media-generation` 스킬에 있습니다. 처음 미디어를 만들기 전에
그 스킬을 먼저 읽습니다.

## 학생의 한국어 요청을 영어로 바꿔서 넘깁니다

학생은 한국어로 말합니다. 그림을 만드는 요청은 영어로 바꿔서 넘겨야
결과가 좋습니다. 학생에게는 이 과정을 말하지 않습니다.

예:
- 학생: "바다에 쓰레기 떠 있는 슬픈 그림"
- 넘길 것: `sad ocean scene with floating plastic trash, children's illustration style, soft colors`

## 그림 요청을 만들 때 규칙

- 초등학생 발표자료에 쓸 그림입니다. 밝고 단순한 그림 스타일을 씁니다.
- 무섭거나 지나치게 슬픈 장면은 만들지 않습니다.
- 사람 얼굴은 만들지 않습니다. 실루엣이나 뒷모습으로 대신합니다.
- 실제 인물·상표·회사 이름을 넣지 않습니다.
- 그림 안에 글자를 넣지 않습니다. 글자는 발표자료에서 넣습니다.
  (글자가 꼭 필요하면 `--kind 대표` 를 씁니다)

## 다 만든 뒤

1. 저장된 파일 위치를 `디자이너` 가 쓸 수 있게 알립니다.
2. `우리팀.md` 의 "만든 것" 목록에 추가합니다.
3. 학생에게는 "포스터가 완성됐어요! 발표자료에 넣어 드릴까요?" 처럼
   결과만 알립니다.

## 영상은 아껴 씁니다

영상은 팀당 2번까지만 만들 수 있습니다. 학생이 영상을 만들고 싶다고 하면
먼저 이렇게 확인합니다:

"영상은 우리 팀이 2번만 만들 수 있어요. 지금 만들까요, 아니면 더 좋은
아이디어가 나올 때까지 아껄까요?"
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-agents-load.sh`
Expected: PASS — 4개 에이전트 모두 로드. 실패하면 `agent/` 대신 `agents/` 로
디렉토리명을 바꿔 재시도한다 (1.18.20 은 둘 다 읽는다).

- [ ] **Step 5: 린트도 통과하는지 확인**

Run: `bash tests/test-lint-preset.sh`
Expected: PASS — 새로 추가된 agent md 4개의 frontmatter 검증도 통과

- [ ] **Step 6: 커밋**

```bash
git add camp-preset/agent tests/test-agents-load.sh
git commit -m "feat: 캠프 에이전트 4종 추가 (도우미/아이디어/디자이너/미디어)

도우미는 primary 로 학생과 직접 대화하고 나머지에 일을 위임한다.
opencode agent list 로 로드를 검증하는 스모크 테스트 포함."
```

---

### Task 4: 미디어 래퍼 `camp-media.sh` — 크레딧 예산 강제

이 프로젝트에서 가장 중요한 코드다. 프롬프트는 지켜지지 않을 수 있지만
스크립트는 반드시 지켜진다. 크레딧 1,360 으로 15팀이 버티는 것이 이 파일에 달려 있다.

**Files:**
- Create: `scripts/camp-media.sh`
- Create: `tests/mock/higgsfield`
- Create: `tests/test-camp-media.sh`

**Interfaces:**
- Consumes: Task 1의 `assert.sh`
- Produces: `camp-media.sh` 명령줄 인터페이스 —
  `camp-media.sh --kind <그림|대표|음악|영상> --prompt <영어 프롬프트> --team-dir <팀폴더> [--name <파일이름>]`
  성공 시 저장된 파일의 팀폴더 기준 상대경로를 stdout 한 줄로 출력한다 (예: `assets/poster-1.png`).
  실패 시 stderr 에 한국어 사유를 쓰고 exit 코드: `2`=영상 횟수 초과, `3`=대표 이미지 횟수 초과, `4`=인자 오류, `5`=생성 실패.
  카운터는 `<팀폴더>/.camp/counts` 에 `영상=N` `대표=N` 형식으로 저장한다.
  Task 5의 `media-generation` 스킬과 Task 12의 E2E 가 이 인터페이스를 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/mock/higgsfield` (실제 크레딧을 쓰지 않는 가짜 CLI):

```bash
#!/usr/bin/env bash
# mock higgsfield. 호출 인자를 기록하고 가짜 결과 URL 을 출력한다.
# MOCK_LOG 에 인자를 append 한다. MOCK_FAIL=1 이면 실패를 흉내낸다.
printf '%s\n' "$*" >> "${MOCK_LOG:-/dev/null}"
if [ "${MOCK_FAIL:-0}" = "1" ]; then
  echo "mock failure" >&2
  exit 1
fi
case "$1 $2" in
  "generate create")
    echo "https://mock.example/out.png"
    ;;
  "account status")
    echo "mock@example.com — plus plan, 999 credits"
    ;;
  *)
    echo "mock: unhandled: $*" >&2; exit 1 ;;
esac
```

`tests/test-camp-media.sh`:

```bash
#!/usr/bin/env bash
# camp-media.sh 단위 테스트. mock higgsfield 를 써서 크레딧을 쓰지 않는다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

SCRIPT="$REPO/scripts/camp-media.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mock 을 PATH 앞에 놓고, 다운로드도 mock 한다
chmod +x "$REPO/tests/mock/higgsfield" 2>/dev/null
export PATH="$REPO/tests/mock:$PATH"
export CAMP_MEDIA_FAKE_DOWNLOAD=1   # 실제 네트워크 다운로드를 건너뛴다

TEAM="$TMP/03조_지구지킴이"
mkdir -p "$TEAM/assets"

# --- 1) 기본 그림은 저가 모델을 쓴다 ---
export MOCK_LOG="$TMP/log1"
: > "$MOCK_LOG"
OUT="$(bash "$SCRIPT" --kind 그림 --prompt "clean ocean illustration" --team-dir "$TEAM" 2>/dev/null)"
assert_eq "$?" "0" "그림 생성이 성공"
assert_contains "$OUT" "assets/" "출력이 assets 상대경로"
assert_contains "$(cat "$MOCK_LOG")" "nano_banana_2_lite" "기본 그림은 nano_banana_2_lite(1크레딧)"
assert_not_contains "$(cat "$MOCK_LOG")" "gpt_image_2" "기본 그림에 고가 모델을 쓰지 않음"

# --- 2) 대표 이미지는 gpt_image_2, 팀당 2회 제한 ---
export MOCK_LOG="$TMP/log2"
: > "$MOCK_LOG"
bash "$SCRIPT" --kind 대표 --prompt "campaign poster" --team-dir "$TEAM" >/dev/null 2>&1
assert_contains "$(cat "$MOCK_LOG")" "gpt_image_2" "대표 이미지는 gpt_image_2"
bash "$SCRIPT" --kind 대표 --prompt "poster 2" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "대표 이미지 2회째는 허용"
bash "$SCRIPT" --kind 대표 --prompt "poster 3" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "3" "대표 이미지 3회째는 거부 (exit 3)"

# --- 3) 음악은 seed_audio, 제한 없음 ---
export MOCK_LOG="$TMP/log3"
: > "$MOCK_LOG"
for i in 1 2 3 4 5; do
  bash "$SCRIPT" --kind 음악 --prompt "gentle ocean bgm" --team-dir "$TEAM" >/dev/null 2>&1
done
assert_eq "$?" "0" "음악은 5회째도 허용"
assert_contains "$(cat "$MOCK_LOG")" "seed_audio" "음악은 seed_audio(0.1크레딧)"

# --- 4) 영상은 seedance_2_0, 팀당 2회 제한 ---
export MOCK_LOG="$TMP/log4"
: > "$MOCK_LOG"
bash "$SCRIPT" --kind 영상 --prompt "ocean cleanup clip" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "영상 1회째 허용"
assert_contains "$(cat "$MOCK_LOG")" "seedance_2_0" "영상은 seedance_2_0"
bash "$SCRIPT" --kind 영상 --prompt "clip 2" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "0" "영상 2회째 허용"
bash "$SCRIPT" --kind 영상 --prompt "clip 3" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "2" "영상 3회째는 거부 (exit 2)"

# --- 5) 카운터가 팀 폴더에 저장된다 ---
assert_file "$TEAM/.camp/counts" "카운터 파일 존재"
assert_contains "$(cat "$TEAM/.camp/counts")" "영상=2" "영상 카운터가 2"

# --- 6) 카운터는 팀별로 독립 ---
TEAM2="$TMP/07조_별빛"
mkdir -p "$TEAM2/assets"
bash "$SCRIPT" --kind 영상 --prompt "other team clip" --team-dir "$TEAM2" >/dev/null 2>&1
assert_eq "$?" "0" "다른 팀은 영상 카운터가 따로임"

# --- 7) 인자 검증 ---
bash "$SCRIPT" --kind 그림 --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "4" "prompt 누락은 exit 4"
bash "$SCRIPT" --kind 이상한것 --prompt "x" --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "4" "알 수 없는 kind 는 exit 4"
bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TMP/없는팀" >/dev/null 2>&1
assert_eq "$?" "4" "없는 팀 폴더는 exit 4"

# --- 8) 생성 실패는 exit 5 와 한국어 메시지 ---
export MOCK_FAIL=1
ERR="$(bash "$SCRIPT" --kind 그림 --prompt "x" --team-dir "$TEAM" 2>&1 >/dev/null)"
assert_eq "$?" "5" "생성 실패는 exit 5"
assert_contains "$ERR" "만들지 못했어요" "실패 메시지가 한국어"
unset MOCK_FAIL

# --- 9) 실패는 카운터를 늘리지 않는다 ---
export MOCK_LOG="$TMP/log9"
BEFORE="$(grep '^영상=' "$TEAM2/.camp/counts" | cut -d= -f2)"
export MOCK_FAIL=1
bash "$SCRIPT" --kind 영상 --prompt "x" --team-dir "$TEAM2" >/dev/null 2>&1
unset MOCK_FAIL
AFTER="$(grep '^영상=' "$TEAM2/.camp/counts" | cut -d= -f2)"
assert_eq "$AFTER" "$BEFORE" "실패 시 영상 카운터가 늘지 않음"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-camp-media.sh`
Expected: FAIL — `scripts/camp-media.sh` 가 없어 모든 어서션 실패

- [ ] **Step 3: `camp-media.sh` 구현**

`scripts/camp-media.sh`:

```bash
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
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-camp-media.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add scripts/camp-media.sh tests/mock/higgsfield tests/test-camp-media.sh
git commit -m "feat: 미디어 래퍼 camp-media.sh — 크레딧 예산 강제

기본 그림은 1크레딧 모델, 대표 이미지 팀당 2회, 영상 팀당 2회로
기계적으로 제한한다. 실패 시 카운터를 올리지 않는다.
mock higgsfield 로 크레딧 없이 단위 테스트한다."
```

---

### Task 5: 미디어 스킬 + 실제 생성 E2E (1크레딧 소모)

**Files:**
- Create: `camp-preset/skills/media-generation/SKILL.md`
- Create: `tests/test-media-e2e.sh`

**Interfaces:**
- Consumes: Task 4의 `camp-media.sh` 인터페이스
- Produces: `media-generation` 스킬 — `미디어` 에이전트가 읽고 `camp-media.sh` 를 올바른 인자로 호출한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-media-e2e.sh`:

```bash
#!/usr/bin/env bash
# 실제 higgsfield 를 호출하는 E2E. 1크레딧을 쓴다.
# CAMP_E2E=1 일 때만 실행한다 (기본은 건너뛴다).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if [ "${CAMP_E2E:-0}" != "1" ]; then
  echo "  skip 실제 크레딧을 쓰는 테스트 (CAMP_E2E=1 로 실행)"
  summary; exit 0
fi

assert_file "$REPO/camp-preset/skills/media-generation/SKILL.md" "media-generation 스킬 존재"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TEAM="$TMP/99조_테스트"
mkdir -p "$TEAM/assets"

REL="$(bash "$REPO/scripts/camp-media.sh" --kind 그림 \
        --prompt "simple flat illustration of a clean blue ocean, children book style" \
        --team-dir "$TEAM" 2>&1)"
assert_eq "$?" "0" "실제 그림 생성 성공"
assert_contains "$REL" "assets/" "상대경로 반환"
assert_file "$TEAM/$REL" "파일이 실제로 저장됨"

SIZE=$(wc -c < "$TEAM/$REL")
if [ "$SIZE" -gt 10000 ]; then pass "파일 크기가 10KB 초과 ($SIZE bytes)"
else fail "파일이 너무 작음 ($SIZE bytes) — 다운로드 실패 의심"; fi

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `CAMP_E2E=1 bash tests/test-media-e2e.sh`
Expected: FAIL — `media-generation 스킬 존재 (파일 없음)`

- [ ] **Step 3: 스킬 구현**

`camp-preset/skills/media-generation/SKILL.md`:

```markdown
---
name: media-generation
description: 캠프에서 그림·음악·영상을 만드는 방법. camp-media.sh 사용법과 비용 규칙을 담고 있다. 미디어를 만들기 전에 반드시 읽는다
---

# 미디어 만들기

## 반드시 `camp-media.sh` 로만 만든다

`higgsfield` 명령을 직접 실행하지 않는다. 그러면 비용 제한이 걸리지 않는다.

```bash
camp-media.sh --kind <그림|대표|음악|영상> --prompt <영어 설명> --team-dir <팀폴더>
```

성공하면 저장된 파일의 상대경로가 한 줄 출력된다. 예: `assets/그림-1.png`

## 네 가지 종류

| kind | 언제 쓰나 | 제한 |
|---|---|---|
| `그림` | 보통의 그림. **기본으로 이걸 쓴다** | 없음. 마음껏 다시 만들어도 된다 |
| `대표` | 발표 표지, 메인 포스터처럼 딱 한 장 중요한 것. 글자가 들어가야 할 때 | **팀당 2번** |
| `음악` | 배경음악, 효과음, 로고송 | 없음 |
| `영상` | 짧은 캠페인 영상 | **팀당 2번** |

**중요:** 학생이 "포스터 만들어 줘" 라고 해도 처음에는 `그림` 을 쓴다.
학생이 마음에 들어하는 그림이 나온 다음, 그것을 발표 표지로 쓸 때만
`대표` 로 한 번 다시 만든다.

## 프롬프트는 영어로 쓴다

학생은 한국어로 말한다. 영어로 바꿔서 넘긴다.

- 학생: "바다에 쓰레기 떠 있는 슬픈 그림"
- `--prompt "sad ocean scene with floating plastic trash, children's illustration style, soft colors, no text"`

프롬프트에 넣을 것:
- 무엇이 보이는지
- `children's illustration style` 또는 `flat vector illustration` 같은 그림 스타일
- `no text` (그림에 글자가 들어가면 이상해진다. `대표` 일 때만 글자를 허용한다)

프롬프트에 넣지 말 것:
- 사람 얼굴, 실제 인물 이름, 실제 상표
- 학생 이름·학교 이름
- 무섭거나 폭력적인 묘사

## 실패했을 때

exit 코드로 무슨 일인지 알 수 있다.

| 코드 | 뜻 | 학생에게 할 말 |
|---|---|---|
| 2 | 영상 횟수 초과 | "영상은 우리 팀이 이미 2번 만들었어요. 만든 영상을 더 멋있게 꾸며 볼까요?" |
| 3 | 대표 그림 횟수 초과 | "표지 그림은 이미 다 만들었어요. 지금 있는 걸로 꾸며 볼까요?" |
| 5 | 생성 실패 | "지금 잘 안 되네요. 한 번만 더 해 볼까요?" |

5번은 한 번만 다시 시도한다. 두 번 연속 실패하면 학생에게 다른 것을
먼저 하자고 제안한다.

## 만든 뒤에

1. 출력된 상대경로를 기억한다. `디자이너` 가 발표자료에 넣을 때 쓴다.
2. `우리팀.md` 의 "만든 것" 목록에 한 줄 추가한다.
3. 학생에게는 결과만 알린다. 파일 경로나 명령을 보여주지 않는다.
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `CAMP_E2E=1 bash tests/test-media-e2e.sh`
Expected: PASS — 실제 이미지 1장 생성(1크레딧), 파일 크기 10KB 초과

- [ ] **Step 5: 크레딧 잔액을 확인해 1크레딧만 줄었는지 검증**

Run: `higgsfield account status`
Expected: 직전 잔액보다 약 1 크레딧 감소

- [ ] **Step 6: 커밋**

```bash
git add camp-preset/skills/media-generation tests/test-media-e2e.sh
git commit -m "feat: media-generation 스킬 + 실제 생성 E2E 테스트

미디어 에이전트가 camp-media.sh 를 올바르게 쓰도록 사용법·비용규칙·
실패 대응을 문서화한다. E2E 는 CAMP_E2E=1 일 때만 실행(1크레딧)."
```

---

### Task 6: 웹슬라이드 템플릿

**Files:**
- Create: `template/index.html`
- Create: `template/우리팀.md`
- Create: `template/assets/.gitkeep`
- Create: `tests/test-template.sh`

**Interfaces:**
- Consumes: Task 1의 `assert.sh`
- Produces: `template/index.html` — `<section class="slide">` 반복 구조, `:root` 의 CSS 변수 테마 4종(`data-theme` 속성으로 전환), 좌우 화살표·스페이스·클릭으로 슬라이드 전환. Task 7의 `web-slides` 스킬과 Task 8의 `디자이너` 동작이 이 구조에 의존한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-template.sh`:

```bash
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
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-template.sh`
Expected: FAIL — `index.html 존재 (파일 없음)`

- [ ] **Step 3: 템플릿 구현**

`template/index.html`:

```html
<!doctype html>
<html lang="ko" data-theme="ocean">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>우리 캠페인</title>
<style>
  :root{
    --bg:#0b2545; --fg:#ffffff; --accent:#5bc0eb; --sub:#a8dadc;
    --font:"맑은 고딕","Malgun Gothic",sans-serif;
  }
  [data-theme="ocean"] { --bg:#0b2545; --fg:#ffffff; --accent:#5bc0eb; --sub:#a8dadc; }
  [data-theme="forest"]{ --bg:#14281d; --fg:#f4fff8; --accent:#7cb518; --sub:#c3e8bd; }
  [data-theme="sunset"]{ --bg:#3d1e2e; --fg:#fff5e1; --accent:#ff8c42; --sub:#ffd9a0; }
  [data-theme="night"] { --bg:#12121c; --fg:#f0f0ff; --accent:#9b8cff; --sub:#c9c4e8; }

  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--fg);font-family:var(--font);overflow:hidden}
  .slide{
    position:absolute;inset:0;display:none;
    flex-direction:column;justify-content:center;align-items:center;
    text-align:center;padding:6vh 8vw;gap:2.4vh;
  }
  .slide.on{display:flex}
  h1{font-size:7vh;line-height:1.2;color:var(--accent)}
  h2{font-size:5vh;line-height:1.25;color:var(--accent)}
  p,li{font-size:3.4vh;line-height:1.5;color:var(--fg)}
  ul{text-align:left;max-width:80%}
  li{margin:1vh 0}
  .team{font-size:3vh;color:var(--sub)}
  .media{max-width:70%;max-height:52vh;border-radius:1.6vh}
  .hint{position:fixed;right:2vw;bottom:2vh;font-size:1.8vh;color:var(--sub);opacity:.7}
  .page{position:fixed;left:2vw;bottom:2vh;font-size:1.8vh;color:var(--sub);opacity:.7}
</style>
</head>
<body>

<!-- 1. 표지 -->
<section class="slide on">
  <h1>캠페인 이름을 여기에</h1>
  <p class="team">00조 팀이름</p>
</section>

<!-- 2. 우리가 찾은 문제 -->
<section class="slide">
  <h2>우리가 찾은 문제</h2>
  <p>어떤 문제를 보고 안타까웠는지 적어요.</p>
</section>

<!-- 3. 우리의 질문 -->
<section class="slide">
  <h2>우리의 질문</h2>
  <p>우리가 어떻게 하면 ○○할 수 있을까?</p>
</section>

<!-- 4. 우리의 캠페인 -->
<section class="slide">
  <h2>우리의 캠페인</h2>
  <ul>
    <li>무엇을 하는 캠페인인지</li>
    <li>누구에게 알리고 싶은지</li>
  </ul>
</section>

<!-- 5. 우리가 만든 것 -->
<section class="slide">
  <h2>우리가 만든 것</h2>
  <p>여기에 우리가 만든 그림이 들어갑니다.</p>
</section>

<!-- 6. 이렇게 실천해요 -->
<section class="slide">
  <h2>이렇게 실천해요</h2>
  <ul>
    <li>오늘부터 할 수 있는 일</li>
    <li>친구들과 함께 할 수 있는 일</li>
  </ul>
</section>

<!-- 7. 우리 팀 -->
<section class="slide">
  <h2>우리 팀</h2>
  <p class="team">00조 팀이름</p>
  <p>들어 주셔서 고맙습니다!</p>
</section>

<div class="page"><span id="now">1</span> / <span id="all">7</span></div>
<div class="hint">← → 눌러서 넘기기</div>

<script>
(function(){
  var slides = document.querySelectorAll('.slide');
  var i = 0;
  document.getElementById('all').textContent = slides.length;
  function show(n){
    if (n < 0) n = 0;
    if (n > slides.length - 1) n = slides.length - 1;
    slides[i].classList.remove('on');
    i = n;
    slides[i].classList.add('on');
    document.getElementById('now').textContent = i + 1;
  }
  document.addEventListener('keydown', function(e){
    if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'PageDown') { show(i+1); }
    if (e.key === 'ArrowLeft'  || e.key === 'PageUp')                   { show(i-1); }
    if (e.key === 'Home') { show(0); }
    if (e.key === 'End')  { show(slides.length-1); }
  });
  document.addEventListener('click', function(e){
    show(e.clientX < window.innerWidth/3 ? i-1 : i+1);
  });
})();
</script>
</body>
</html>
```

`template/우리팀.md`:

```markdown
# 우리 팀 기록

이 파일은 도우미가 읽고 쓰는 기록장입니다. 학생이 직접 고치지 않아도 됩니다.

- 조 번호: (아직 안 정함)
- 팀 이름: (아직 안 정함)
- 트랙: (AI·디지털 / 지구·환경 중 하나)
- 우리가 찾은 문제: (아직 안 정함)
- 우리의 질문(How Might We): (아직 안 정함)
- 캠페인 이름: (아직 안 정함)
- 발표자료 색 테마: ocean

## 만든 것

(아직 없음)

## 다음에 할 일

- 팀 이름 정하기
```

`template/assets/.gitkeep`: 빈 파일

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-template.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 브라우저에서 실제로 열어 눈으로 확인**

Run: `start template/index.html` (Windows) 또는 `cmd //c start template\\index.html`
확인 사항: 표지가 보인다 · 오른쪽 화살표로 7장까지 넘어간다 · 왼쪽 화살표로 돌아온다 · 글자가 크고 읽기 쉽다 · 오른쪽 아래에 조작 안내가 보인다

- [ ] **Step 6: 커밋**

```bash
git add template tests/test-template.sh
git commit -m "feat: 웹슬라이드 발표자료 템플릿

외부 리소스 없는 단일 HTML. 슬라이드 7장 골격, 색 테마 4종,
좌우 화살표·스페이스·클릭 전환. 오프라인에서 동작한다."
```

---

### Task 7: 슬라이드 편집 스킬 + 캠페인 기획 스킬 + 발표대본 스킬

**Files:**
- Create: `camp-preset/skills/web-slides/SKILL.md`
- Create: `camp-preset/skills/campaign-planning/SKILL.md`
- Create: `camp-preset/skills/presentation-script/SKILL.md`
- Create: `tests/test-skills.sh`

**Interfaces:**
- Consumes: Task 6의 `template/index.html` 구조(`class="slide"`, `data-theme`), Task 2의 `AGENTS.md` 용어
- Produces: 스킬 3종. `디자이너`/`아이디어` 에이전트가 읽는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-skills.sh`:

```bash
#!/usr/bin/env bash
# 스킬 파일의 frontmatter 와 필수 내용을 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

for s in media-generation web-slides campaign-planning presentation-script; do
  F="$REPO/camp-preset/skills/$s/SKILL.md"
  assert_file "$F" "스킬 파일 존재: $s"
  [ -f "$F" ] || continue
  head -1 "$F" | grep -q '^---$'
  assert_eq "$?" "0" "frontmatter 시작: $s"
  NAME="$(grep -m1 '^name:' "$F" | sed 's/^name:[[:space:]]*//')"
  assert_eq "$NAME" "$s" "name 이 디렉토리명과 일치: $s"
  grep -q '^description:' "$F"
  assert_eq "$?" "0" "description 존재: $s"
done

# web-slides 는 템플릿 구조를 정확히 참조해야 한다
W="$(cat "$REPO/camp-preset/skills/web-slides/SKILL.md" 2>/dev/null || echo '')"
assert_contains "$W" 'class="slide"' "web-slides 가 slide 클래스를 명시"
assert_contains "$W" "data-theme" "web-slides 가 테마 전환 방법을 명시"
assert_contains "$W" "ocean" "web-slides 가 테마 이름을 명시"
# 스킬은 지시문이므로 빌드 도구를 "금지 조항으로" 담아야 한다
assert_contains "$W" "빌드 도구를 쓰지 않는다" "web-slides 가 빌드 도구를 금지"
assert_contains "$W" "외부 URL" "web-slides 가 외부 리소스를 금지"

# campaign-planning 은 HMW 절차를 담아야 한다
C="$(cat "$REPO/camp-preset/skills/campaign-planning/SKILL.md" 2>/dev/null || echo '')"
assert_contains "$C" "How Might We" "campaign-planning 에 HMW"
assert_contains "$C" "우리팀.md" "campaign-planning 이 기록 파일을 명시"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-skills.sh`
Expected: FAIL — `web-slides`, `campaign-planning`, `presentation-script` 파일 없음

- [ ] **Step 3: 스킬 3종 구현**

`camp-preset/skills/web-slides/SKILL.md`:

```markdown
---
name: web-slides
description: 발표자료 index.html 의 구조와 편집 규칙. 슬라이드를 추가·수정하거나 색 테마를 바꿀 때 읽는다
---

# 발표자료 편집 규칙

발표자료는 팀 폴더의 `index.html` 파일 하나다.

## 절대 규칙

- 외부 URL 을 넣지 않는다. CDN, 웹폰트, 외부 스크립트 금지.
  캠프장 인터넷이 끊겨도 발표가 되어야 한다.
- `npm`, 번들러, 프레임워크를 쓰지 않는다. 순수 HTML/CSS/JS 만.
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
```

`camp-preset/skills/campaign-planning/SKILL.md`:

```markdown
---
name: campaign-planning
description: 디자인씽킹 절차로 팀의 과학 캠페인 주제를 정하는 방법. How Might We 질문 만들기와 캠페인 이름 짓기를 포함한다
---

# 캠페인 기획 절차

디자인씽킹의 "공감 → 문제 정의 → 아이디어 발산" 을 초등학생 눈높이로
진행한다. 한 번에 한 단계씩만 진행한다.

## 1단계 — 트랙 확인

`AI·디지털` 인가 `지구·환경` 인가. `우리팀.md` 에 이미 있으면 묻지 않는다.

## 2단계 — 문제 찾기 (공감)

학생 **자신의 경험**에서 출발한다. 어른의 문제가 아니다.

이렇게 묻는다:
"우리 학교나 동네에서, 보면서 '이건 좀 아쉽다' 싶었던 게 있어요?"

학생이 막히면 트랙에 맞는 예를 3개만 준다.
- 지구·환경: 급식 남는 음식, 교실에 켜 둔 불, 길에 버려진 페트병
- AI·디지털: 스마트폰을 너무 오래 보는 것, 모르는 링크, 흐릿한 정보

## 3단계 — How Might We 질문 만들기 (문제 정의)

찾은 문제를 질문으로 바꾼다.

형태: **"우리가 어떻게 하면 ○○할 수 있을까?"**

3개를 만들어 제안하고 하나를 고르게 한다. 각각 한 줄로 짧게.

예:
1. 우리가 어떻게 하면 급식을 남기지 않게 할 수 있을까?
2. 우리가 어떻게 하면 남은 음식이 어디로 가는지 알게 할 수 있을까?
3. 우리가 어떻게 하면 급식 남기기가 부끄러운 일이 되게 할 수 있을까?

## 4단계 — 캠페인 이름 짓기

고른 질문에 맞는 이름 3개를 제안한다. 짧고, 기억하기 쉽고, 초등학생이
발표할 때 자랑스러운 이름으로.

## 5단계 — 크기 줄이기

5시간 안에 만들 수 있어야 한다. 학생이 너무 큰 것을 원하면:

"이 중에서 우리가 제일 잘 보여줄 수 있는 하나만 골라 볼까요?
하나를 제대로 하면 훨씬 멋있어요."

## 6단계 — 기록

정해진 것을 `우리팀.md` 에 적는다: 조 번호, 팀 이름, 트랙, 찾은 문제,
How Might We 질문, 캠페인 이름. 그리고 "다음에 할 일" 을 갱신한다.

학생 이름·학교는 적지 않는다.
```

`camp-preset/skills/presentation-script/SKILL.md`:

```markdown
---
name: presentation-script
description: 팀별 발표 대본을 만들고 발표 연습을 돕는 방법. 4명이 나눠 말하도록 배분한다
---

# 발표 대본 만들기

발표는 9월 20일 오전, 팀별로 한다. 팀은 4명이다.

## 대본 규칙

- 전체 발표는 **2분 안쪽**으로 맞춘다. 슬라이드 7장이면 한 장에 약 15초.
- 4명이 **모두 말하도록** 나눈다. 한 명이 다 하지 않는다.
- 각자 맡은 부분을 `1번 친구`, `2번 친구` 처럼 번호로 표시한다.
  **이름을 쓰지 않는다.**
- 초등학생이 실제로 말할 수 있는 문장으로 쓴다. 한 문장은 짧게.
- 어려운 낱말을 쓰지 않는다.

## 대본 형식

`발표대본.md` 파일로 팀 폴더에 저장한다.

```markdown
# 발표 대본 (약 2분)

## 1장 표지 — 1번 친구 (15초)
안녕하세요! 저희는 03조 지구지킴이입니다.
저희 캠페인 이름은 "남기지 말자 오늘 급식" 입니다.

## 2장 우리가 찾은 문제 — 2번 친구 (20초)
...
```

## 발표 연습을 도울 때

1. 대본을 만들어 보여준다.
2. "1번 친구부터 소리 내서 읽어 볼까요?" 라고 권한다.
3. 너무 길면 문장을 줄여 준다. 학생이 읽다가 막히는 낱말은 쉬운 말로 바꾼다.
4. 마지막에 "다 같이 인사하는 연습" 을 넣는다.

## 하지 않는 것

- 학생 이름을 대본에 넣지 않는다.
- 발표를 녹화하거나 인터넷에 올리자고 제안하지 않는다.
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-skills.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add camp-preset/skills tests/test-skills.sh
git commit -m "feat: 스킬 3종 추가 (web-slides / campaign-planning / presentation-script)

web-slides 는 템플릿 구조를 정확히 참조하고 외부 리소스를 금지한다.
campaign-planning 은 HMW 절차를 초등학생 눈높이로 담는다.
presentation-script 는 4명 분담 대본을 실명 없이 만든다."
```

---

### Task 8: 한국어 슬래시 명령어 10종

`opencode run` 은 슬래시 명령을 파일 경로로 해석하므로 명령어 자체는
비대화형으로 실행할 수 없다. 따라서 검증은 두 갈래로 한다:
(a) 파일·frontmatter 정적 검증, (b) 명령어 **본문을 프롬프트로 직접 먹여**
의도한 동작이 나오는지 확인.

**Files:**
- Create: `camp-preset/command/시작.md`, `아이디어.md`, `포스터.md`, `음악.md`, `영상.md`, `슬라이드추가.md`, `보여줘.md`, `발표연습.md`, `제출.md`, `도와줘.md`
- Create: `tests/test-commands.sh`

**Interfaces:**
- Consumes: Task 3의 에이전트 이름(`도우미`/`아이디어`/`디자이너`/`미디어`), Task 4의 `camp-media.sh` 인터페이스, Task 6의 템플릿 구조
- Produces: 명령어 10종. 학생이 TUI 에서 `/시작` 처럼 입력한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-commands.sh`:

```bash
#!/usr/bin/env bash
# 명령어 파일 10종의 정적 검증 + 본문 프롬프트 프록시 검증.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

CMDS="시작 아이디어 포스터 음악 영상 슬라이드추가 보여줘 발표연습 제출 도와줘"
VALID_AGENTS="도우미 아이디어 디자이너 미디어"

for c in $CMDS; do
  F="$REPO/camp-preset/command/$c.md"
  assert_file "$F" "명령어 존재: /$c"
  [ -f "$F" ] || continue
  grep -q '^description:' "$F"
  assert_eq "$?" "0" "description 존재: /$c"
  # agent 를 지정했다면 실재하는 에이전트여야 한다
  A="$(grep -m1 '^agent:' "$F" | sed 's/^agent:[[:space:]]*//')"
  if [ -n "$A" ]; then
    case " $VALID_AGENTS " in
      *" $A "*) pass "agent 유효: /$c → $A" ;;
      *) fail "agent 가 존재하지 않음: /$c → $A" ;;
    esac
  fi
  # 학생 대면 금지 용어가 본문에 없어야 한다 (에이전트 지시문은 예외 없음)
  # frontmatter(--- 로 감싼 두 줄) 이후의 본문만 뽑는다
  BODY="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
  assert_not_contains "$BODY" "터미널" "금지 용어 없음(터미널): /$c"
done

# /보여줘 는 브라우저를 여는 방법을 명시해야 한다
S="$(cat "$REPO/camp-preset/command/보여줘.md" 2>/dev/null || echo '')"
assert_contains "$S" "start" "/보여줘 가 브라우저 여는 명령을 포함"

# /포스터 는 camp-media.sh 를 쓰도록 지시해야 한다
P="$(cat "$REPO/camp-preset/command/포스터.md" 2>/dev/null || echo '')"
assert_contains "$P" "camp-media.sh" "/포스터 가 래퍼를 사용"
assert_not_contains "$P" "higgsfield generate" "/포스터 가 CLI 를 직접 쓰지 않음"

# /영상 은 횟수 제한을 학생에게 알려야 한다
V="$(cat "$REPO/camp-preset/command/영상.md" 2>/dev/null || echo '')"
assert_contains "$V" "2번" "/영상 이 횟수 제한을 안내"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-commands.sh`
Expected: FAIL — 10개 명령어 파일 모두 없음

- [ ] **Step 3: 명령어 10종 구현**

`camp-preset/command/시작.md`:

```markdown
---
description: 캠프를 시작합니다. 팀 이름과 트랙을 정하고 캠페인 주제를 잡습니다
agent: 아이디어
---
`우리팀.md` 를 읽어라. 이미 정해진 것이 있으면 그것을 확인만 하고
아직 안 정해진 첫 항목부터 이어서 진행하라.

`campaign-planning` 스킬을 읽고 그 절차를 따르라.
한 번에 한 단계만 진행하라.

아무것도 안 정해져 있으면 이렇게 시작하라:
"안녕하세요! 같이 멋진 캠페인을 만들어 봐요. 먼저 우리 조는 몇 조예요?"
```

`camp-preset/command/아이디어.md`:

```markdown
---
description: 우리 팀 캠페인 아이디어를 함께 정합니다
agent: 아이디어
---
`campaign-planning` 스킬의 2~5단계(문제 찾기 → How Might We → 캠페인 이름)를
진행하라. `우리팀.md` 를 먼저 읽어 어디까지 진행됐는지 확인하고
그 다음 단계부터 시작하라.

한 번에 한 가지만 물어라. 선택지는 3개까지.
```

`camp-preset/command/포스터.md`:

```markdown
---
description: 캠페인 포스터나 그림을 만듭니다
agent: 미디어
---
$ARGUMENTS

`media-generation` 스킬을 읽어라.

학생이 어떤 그림을 원하는지 아직 모르면 한 가지만 물어라:
"어떤 그림을 만들까요? 예를 들면 '바다에 쓰레기가 떠 있는 그림' 처럼요."

원하는 것을 알았으면 `camp-media.sh --kind 그림` 으로 만들어라.
처음에는 반드시 `--kind 그림` 을 쓴다. `--kind 대표` 는 학생이 마음에
들어하는 그림을 발표 표지로 확정할 때만 쓴다.

`우리팀.md` 를 읽어 캠페인 주제를 반영한 영어 프롬프트를 만들어라.

다 만들면 학생에게 결과만 알리고, 발표자료에 넣어 줄지 물어라.
```

`camp-preset/command/음악.md`:

```markdown
---
description: 캠페인 배경음악이나 로고송을 만듭니다
agent: 미디어
---
$ARGUMENTS

`media-generation` 스킬을 읽어라.

`camp-media.sh --kind 음악` 으로 만들어라. 음악은 횟수 제한이 없으니
학생이 마음에 들어할 때까지 다시 만들어 줘도 된다.

`우리팀.md` 의 캠페인 주제에 어울리는 분위기를 영어 프롬프트로 만들어라.
예: `gentle hopeful background music for a children's environmental campaign, soft piano`

다 만들면 발표자료에 넣어 줄지 물어라.
```

`camp-preset/command/영상.md`:

```markdown
---
description: 짧은 캠페인 영상을 만듭니다 (팀당 2번까지)
agent: 미디어
---
$ARGUMENTS

`media-generation` 스킬을 읽어라.

영상은 팀당 **2번**까지만 만들 수 있다. 만들기 전에 반드시 확인하라:

"영상은 우리 팀이 2번만 만들 수 있어요. 지금 만들까요?
아니면 더 좋은 생각이 날 때까지 아껄까요?"

학생이 만들자고 하면 `camp-media.sh --kind 영상` 으로 만들어라.
횟수를 다 썼다는 오류가 나오면 이미 만든 영상을 더 멋있게 꾸미자고
제안하라.
```

`camp-preset/command/슬라이드추가.md`:

```markdown
---
description: 발표자료에 새 장을 추가합니다
agent: 디자이너
---
$ARGUMENTS

`web-slides` 스킬을 읽어라. `index.html` 과 `우리팀.md` 를 읽어라.

학생이 어떤 장을 원하는지 모르면 한 가지만 물어라:
"어떤 내용을 넣을까요?"

새 `<section class="slide">` 를 `<div class="page">` 바로 위에 추가하라.
글은 5줄 이내로. 외부 URL 을 넣지 마라.

다 하면 이렇게 알려라:
"새 장을 넣었어요! `/보여줘` 라고 쓰면 볼 수 있어요."
```

`camp-preset/command/보여줘.md`:

```markdown
---
description: 지금까지 만든 발표자료를 브라우저로 열어서 봅니다
agent: 도우미
---
팀 폴더의 `index.html` 을 기본 브라우저로 열어라.

Windows 에서는 이렇게 한다:

!`cmd //c start "" index.html`

열고 나서 학생에게 이렇게 말하라:

"발표자료를 열었어요! 화살표 키를 눌러서 넘겨 보세요.
고치고 싶은 게 있으면 말해 주세요."

파일 경로나 명령을 학생에게 보여주지 마라.
```

`camp-preset/command/발표연습.md`:

```markdown
---
description: 발표 대본을 만들고 발표 연습을 합니다
agent: 도우미
---
`presentation-script` 스킬을 읽어라.
`index.html` 과 `우리팀.md` 를 읽어 지금 발표자료에 무엇이 있는지 파악하라.

4명이 나눠 말하는 2분 대본을 만들어 `발표대본.md` 로 저장하라.
이름 대신 `1번 친구` 처럼 번호를 쓰라.

만든 다음 "1번 친구부터 소리 내서 읽어 볼까요?" 라고 권하라.
```

`camp-preset/command/제출.md`:

```markdown
---
description: 완성한 발표자료를 제출용으로 묶습니다
agent: 도우미
---
`우리팀.md` 를 읽어 조 번호와 팀 이름을 확인하라.
아직 없으면 조 번호와 팀 이름을 물어라 (이름은 묻지 마라).

발표자료와 만든 것들을 하나로 묶어라. 팀 폴더의 부모 디렉토리에
`NN조_팀이름.zip` 으로 만든다. `.camp` 폴더는 제외한다.

!`powershell -NoProfile -Command "Compress-Archive -Path 'index.html','assets','우리팀.md' -DestinationPath '../제출.zip' -Force"`

만든 뒤 파일 이름을 조 번호와 팀 이름에 맞게 바꿔라.

학생에게는 이렇게 말하라:
"제출 파일을 만들었어요! 선생님께 알려 드리면 돼요. 정말 수고했어요!"

묶기 전에 다음을 확인하라. 빠진 것이 있으면 학생에게 알려라.
- 표지에 캠페인 이름과 팀 이름이 들어갔는가
- "우리가 만든 것" 장에 그림이나 영상이 들어갔는가
- 발표자료 어디에도 학생 실명이 없는가
```

`camp-preset/command/도와줘.md`:

```markdown
---
description: 지금 무엇을 하면 좋을지 알려 줍니다
agent: 도우미
---
`우리팀.md` 와 `index.html` 을 읽어라.

지금까지 무엇이 되어 있고 무엇이 비어 있는지 파악한 다음,
**다음에 할 일 하나만** 콕 집어 제안하라. 여러 개를 나열하지 마라.

순서는 보통 이렇다:
1. 조 번호와 팀 이름 정하기
2. 트랙 정하기
3. 문제 찾기와 How Might We 질문 만들기
4. 캠페인 이름 정하기
5. 그림 만들기
6. 발표자료에 장 채우기
7. 음악이나 영상 넣기
8. 발표 대본 만들기
9. 제출하기

제안할 때 그 일을 시작하는 명령어도 함께 알려 줘라.
예: "이제 포스터를 만들어 볼까요? `/포스터` 라고 써 보세요!"

그리고 지금까지 한 것을 하나 구체적으로 칭찬하라.
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-commands.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 명령어 본문을 프롬프트로 먹여 동작 확인 (프록시 검증)**

Run:
```bash
CFG="$(cygpath -m "$PWD/camp-preset")"
cd /tmp && rm -rf cmdtest && mkdir cmdtest && cd cmdtest
cp -r "$OLDPWD/template/." .
BODY="$(awk '/^---$/{n++; next} n>=2{print}' "$OLDPWD/camp-preset/command/도와줘.md")"
OPENCODE_CONFIG_DIR="$CFG" opencode run "$BODY" --agent 도우미
```
Expected: 다음 할 일 **하나만** 제안하고, 명령어를 알려주고, 칭찬이 들어 있다. 여러 개를 나열하면 `도와줘.md` 의 지시를 강화한다.

- [ ] **Step 6: 커밋**

```bash
git add camp-preset/command tests/test-commands.sh
git commit -m "feat: 한국어 슬래시 명령어 10종

시작/아이디어/포스터/음악/영상/슬라이드추가/보여줘/발표연습/제출/도와줘.
agent frontmatter 가 실재 에이전트를 가리키는지, 포스터가 래퍼를 쓰는지,
영상이 횟수 제한을 안내하는지 검증한다."
```

---

### Task 9: 팀 폴더 생성 스크립트

**Files:**
- Create: `scripts/new-team.sh`
- Create: `tests/test-new-team.sh`

**Interfaces:**
- Consumes: Task 6의 `template/`
- Produces: `new-team.sh <조번호> <팀이름> [부모디렉토리]` — 팀 폴더를 만들고 템플릿을 복사하고 `우리팀.md` 의 조번호·팀이름을 채운다. 성공 시 만든 폴더의 절대경로를 stdout 에 출력. exit 4=인자 오류, 5=이미 존재.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-new-team.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"
S="$REPO/scripts/new-team.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

DIR="$(bash "$S" 3 지구지킴이 "$TMP" 2>/dev/null)"
assert_eq "$?" "0" "팀 폴더 생성 성공"
assert_contains "$DIR" "03조_지구지킴이" "조번호가 두 자리로 정규화됨"
assert_file "$DIR/index.html" "index.html 복사됨"
assert_file "$DIR/우리팀.md" "우리팀.md 복사됨"
if [ -d "$DIR/assets" ]; then pass "assets 폴더 생성"; else fail "assets 폴더 없음"; fi

TEAMDOC="$(cat "$DIR/우리팀.md")"
assert_contains "$TEAMDOC" "조 번호: 03조" "우리팀.md 에 조번호 기입"
assert_contains "$TEAMDOC" "팀 이름: 지구지킴이" "우리팀.md 에 팀이름 기입"
assert_not_contains "$TEAMDOC" "팀 이름: (아직 안 정함)" "팀 이름 자리표시자가 남지 않음"
assert_not_contains "$TEAMDOC" "조 번호: (아직 안 정함)" "조 번호 자리표시자가 남지 않음"

HTML="$(cat "$DIR/index.html")"
assert_contains "$HTML" "03조 지구지킴이" "표지에 조번호·팀이름 반영"
assert_not_contains "$HTML" "00조 팀이름" "표지 자리표시자가 남지 않음"

# 두 번째 호출은 거부
bash "$S" 3 지구지킴이 "$TMP" >/dev/null 2>&1
assert_eq "$?" "5" "이미 있는 팀은 exit 5"

# 인자 검증
bash "$S" >/dev/null 2>&1
assert_eq "$?" "4" "인자 없으면 exit 4"
bash "$S" 0 팀 "$TMP" >/dev/null 2>&1
assert_eq "$?" "4" "조번호 0 은 exit 4"
bash "$S" 16 팀 "$TMP" >/dev/null 2>&1
assert_eq "$?" "4" "조번호 16 은 exit 4 (15개 조)"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-new-team.sh`
Expected: FAIL — `scripts/new-team.sh` 없음

- [ ] **Step 3: 구현**

`scripts/new-team.sh`:

```bash
#!/usr/bin/env bash
# 팀 폴더를 만들고 발표자료 템플릿을 넣는다.
# 사용법: new-team.sh <조번호 1-15> <팀이름> [부모디렉토리]
# 성공: 만든 폴더의 절대경로를 stdout 출력. exit 4=인자오류, 5=이미존재
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NUM="${1:-}"; NAME="${2:-}"; PARENT="${3:-$PWD}"

[ -n "$NUM" ] && [ -n "$NAME" ] || { echo "조 번호와 팀 이름이 필요해요." >&2; exit 4; }
case "$NUM" in ''|*[!0-9]*) echo "조 번호는 숫자여야 해요." >&2; exit 4 ;; esac
if [ "$NUM" -lt 1 ] || [ "$NUM" -gt 15 ]; then
  echo "조 번호는 1부터 15까지예요." >&2; exit 4
fi
case "$NAME" in *[/\\:*?\"\<\>\|]*) echo "팀 이름에 쓸 수 없는 글자가 있어요." >&2; exit 4 ;; esac

PAD="$(printf '%02d' "$NUM")"
DIR="$PARENT/${PAD}조_${NAME}"

[ -e "$DIR" ] && { echo "이미 있는 팀 폴더예요: ${PAD}조_${NAME}" >&2; exit 5; }

mkdir -p "$DIR"
cp -r "$REPO/template/." "$DIR/"
mkdir -p "$DIR/assets"

# 조번호·팀이름 채우기
python - "$DIR" "$PAD" "$NAME" <<'PY'
import io, sys, os
d, pad, name = sys.argv[1], sys.argv[2], sys.argv[3]

p = os.path.join(d, "우리팀.md")
s = io.open(p, encoding="utf-8").read()
s = s.replace("- 조 번호: (아직 안 정함)", "- 조 번호: %s조" % pad)
s = s.replace("- 팀 이름: (아직 안 정함)", "- 팀 이름: %s" % name)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)

p = os.path.join(d, "index.html")
s = io.open(p, encoding="utf-8").read()
s = s.replace("00조 팀이름", "%s조 %s" % (pad, name))
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
PY

printf '%s\n' "$DIR"
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-new-team.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add scripts/new-team.sh tests/test-new-team.sh
git commit -m "feat: 팀 폴더 생성 스크립트 new-team.sh

조번호를 두 자리로 정규화하고 템플릿을 복사한 뒤
우리팀.md 와 표지의 조번호·팀이름 자리표시자를 채운다.
조번호는 1~15 로 제한(15개 조)."
```

---

### Task 10: 프리셋 설치 스크립트

**Files:**
- Create: `scripts/install-preset.sh`
- Create: `tests/test-install-preset.sh`

**Interfaces:**
- Consumes: `camp-preset/` 전체
- Produces: `install-preset.sh [--target <디렉토리>] [--force]` — 기본 대상은 `~/.config/opencode`. 기존 내용이 있으면 `<대상>.backup-<타임스탬프>` 로 옮긴 뒤 설치한다. `--target` 으로 테스트용 임시 디렉토리를 지정할 수 있다. exit 6=대상이 이미 있고 `--force` 없음.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-install-preset.sh`:

```bash
#!/usr/bin/env bash
# 설치 스크립트가 기존 설정을 덮어쓰지 않는지 검증한다.
# 개발자의 실제 ~/.config/opencode 는 절대 건드리지 않는다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"
S="$REPO/scripts/install-preset.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1) 빈 대상에 설치
T1="$TMP/cfg1"
bash "$S" --target "$T1" >/dev/null 2>&1
assert_eq "$?" "0" "빈 대상에 설치 성공"
assert_file "$T1/AGENTS.md" "AGENTS.md 설치됨"
assert_file "$T1/opencode.json" "opencode.json 설치됨"
assert_file "$T1/agent/도우미.md" "에이전트 설치됨"
assert_file "$T1/command/시작.md" "명령어 설치됨"
assert_file "$T1/skills/web-slides/SKILL.md" "스킬 설치됨"

# 2) 이미 있는 대상은 --force 없이 거부
bash "$S" --target "$T1" >/dev/null 2>&1
assert_eq "$?" "6" "기존 대상은 --force 없이 거부 (exit 6)"

# 3) --force 는 백업을 만든 뒤 설치
echo "내 원래 설정" > "$T1/내파일.txt"
bash "$S" --target "$T1" --force >/dev/null 2>&1
assert_eq "$?" "0" "--force 로 재설치 성공"
BK="$(ls -d "$T1".backup-* 2>/dev/null | head -1)"
if [ -n "$BK" ]; then pass "백업 디렉토리 생성"; else fail "백업이 만들어지지 않음"; fi
assert_file "$BK/내파일.txt" "기존 파일이 백업에 보존됨"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-install-preset.sh`
Expected: FAIL — `scripts/install-preset.sh` 없음

- [ ] **Step 3: 구현**

`scripts/install-preset.sh`:

```bash
#!/usr/bin/env bash
# 캠프 프리셋을 opencode 설정 디렉토리에 설치한다.
# 사용법: install-preset.sh [--target <디렉토리>] [--force]
# exit 6 = 대상이 이미 있고 --force 가 없음
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${HOME}/.config/opencode"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 4 ;;
  esac
done

if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "이미 설정이 있습니다: $TARGET" >&2
    echo "덮어쓰려면 --force 를 쓰세요. 기존 설정은 백업됩니다." >&2
    exit 6
  fi
  TS="$(date +%Y%m%d-%H%M%S)"
  BK="${TARGET}.backup-${TS}"
  mv "$TARGET" "$BK"
  echo "기존 설정을 백업했습니다: $BK"
fi

mkdir -p "$TARGET"
cp -r "$REPO/camp-preset/." "$TARGET/"
echo "설치 완료: $TARGET"
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-install-preset.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add scripts/install-preset.sh tests/test-install-preset.sh
git commit -m "feat: 프리셋 설치 스크립트 install-preset.sh

기존 설정이 있으면 --force 를 요구하고 타임스탬프 백업을 만든 뒤
설치한다. --target 으로 임시 디렉토리 설치를 지원해 테스트가
개발자의 실제 설정을 건드리지 않는다."
```

---

### Task 11: 초5 시뮬레이션 E2E

전체가 실제로 이어지는지 확인한다. 사양의 성공 판정 — "초5 학생이 어른
도움 없이 20분 안에 팀 컨셉 → 슬라이드 3장 → AI 이미지 1장" — 을 검증한다.

**Files:**
- Create: `tests/test-e2e-scenario.sh`

**Interfaces:**
- Consumes: Task 1~10 전체
- Produces: 없음 (최종 검증)

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-e2e-scenario.sh`:

```bash
#!/usr/bin/env bash
# 초5 학생 시뮬레이션 E2E. 실제 모델과 실제 미디어 생성을 쓴다.
# CAMP_E2E=1 일 때만 실행한다 (1크레딧 + DeepSeek 토큰 소모).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

if [ "${CAMP_E2E:-0}" != "1" ]; then
  echo "  skip 실제 API 를 쓰는 테스트 (CAMP_E2E=1 로 실행)"
  summary; exit 0
fi

CFG="$REPO/camp-preset"
command -v cygpath >/dev/null 2>&1 && CFG="$(cygpath -m "$CFG")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 팀 폴더 만들기
TEAM="$(bash "$REPO/scripts/new-team.sh" 9 바다친구 "$TMP")"
assert_eq "$?" "0" "팀 폴더 생성"
cd "$TEAM" || exit 1

run() {
  OPENCODE_CONFIG_DIR="$CFG" PATH="$REPO/scripts:$PATH" \
    opencode run "$1" --agent "${2:-도우미}" 2>&1
}

# --- 1) 초등학생 말투 확인 ---
R1="$(run '안녕! 나 뭐부터 해야 돼?')"
assert_contains "$R1" "요" "존댓말로 답함"
assert_not_contains "$R1" "터미널" "터미널 용어 미사용"
assert_not_contains "$R1" "HTML" "HTML 용어 미사용"
assert_not_contains "$R1" "디렉토리" "디렉토리 용어 미사용"

# --- 2) 이름을 물어도 기록하지 않음 ---
R2="$(run '내 이름은 김하늘이야. 발표자료에 내 이름 넣어줘.')"
assert_not_contains "$(cat "$TEAM/index.html")" "김하늘" "실명이 발표자료에 안 들어감"
assert_not_contains "$(cat "$TEAM/우리팀.md")" "김하늘" "실명이 기록에 안 들어감"

# --- 3) 캠페인 주제 정하기 ---
run '우리는 지구·환경 트랙이야. 급식 남기는 게 아쉬웠어. 캠페인 주제 정해줘.' 아이디어 >/dev/null
TEAMDOC="$(cat "$TEAM/우리팀.md")"
assert_not_contains "$TEAMDOC" "트랙: (AI·디지털 / 지구·환경 중 하나)" "트랙이 기록됨"

# --- 4) 그림 만들어 발표자료에 넣기 (1크레딧) ---
run '급식 남기지 말자는 그림 하나 만들어서 발표자료에 넣어줘.' >/dev/null
IMGS="$(ls "$TEAM/assets" 2>/dev/null | grep -cE '\.(png|jpg)$' || echo 0)"
if [ "$IMGS" -ge 1 ]; then pass "그림이 assets 에 생성됨 ($IMGS)"
else fail "그림이 생성되지 않음"; fi
assert_contains "$(cat "$TEAM/index.html")" "assets/" "발표자료가 그림을 상대경로로 참조"

# --- 5) 슬라이드 추가 ---
BEFORE=$(grep -o 'class="slide' "$TEAM/index.html" | wc -l | tr -d ' ')
run '"우리가 만든 것" 다음에 실천 방법 장을 하나 더 넣어줘.' 디자이너 >/dev/null
AFTER=$(grep -o 'class="slide' "$TEAM/index.html" | wc -l | tr -d ' ')
if [ "$AFTER" -gt "$BEFORE" ]; then pass "슬라이드가 늘어남 ($BEFORE → $AFTER)"
else fail "슬라이드가 늘지 않음 ($BEFORE → $AFTER)"; fi

# --- 6) 발표자료가 여전히 오프라인에서 열림 ---
H="$(cat "$TEAM/index.html")"
assert_not_contains "$H" "https://" "외부 URL 이 추가되지 않음"
assert_not_contains "$H" "cdn" "CDN 이 추가되지 않음"
assert_not_contains "$H" "npm" "빌드 도구가 추가되지 않음"

# --- 7) 영상 한도 초과가 실제로 막히는지 ---
# 주의: 여기서 실제 영상을 만들면 22.5크레딧이 날아간다.
# 카운터를 직접 한도까지 올려놓고 차단만 확인한다.
mkdir -p "$TEAM/.camp"
printf '영상=2\n' > "$TEAM/.camp/counts"
bash "$REPO/scripts/camp-media.sh" --kind 영상 --prompt x --team-dir "$TEAM" >/dev/null 2>&1
assert_eq "$?" "2" "영상 한도 초과가 실제로 차단됨 (크레딧 소모 없음)"

summary
```

- [ ] **Step 2: 테스트를 실행해 실패 지점을 확인**

Run: `CAMP_E2E=1 bash tests/test-e2e-scenario.sh`
Expected: 일부 항목 FAIL 가능. 프롬프트 문제이므로 아래 순서로 고친다.
- 존댓말·용어 위반 → `AGENTS.md` 의 금지 용어 목록 강화
- 실명 기록 → `AGENTS.md` 개인정보 규칙 강화
- 슬라이드 안 늘어남 → `web-slides` 스킬의 삽입 위치 설명 강화
- 외부 URL 추가됨 → `web-slides` 스킬의 금지 규칙을 맨 위로 올림

- [ ] **Step 3: 실패한 항목에 맞춰 프리셋을 수정**

프리셋(프롬프트) 파일만 고친다. 테스트를 느슨하게 바꾸지 않는다.
테스트가 요구하는 것은 사양의 성공 판정 그대로다.

- [ ] **Step 4: 전체 테스트를 실행해 통과를 확인**

Run: `bash tests/run-all.sh` 그리고 `CAMP_E2E=1 bash tests/test-e2e-scenario.sh`
Expected: 둘 다 PASS

- [ ] **Step 5: 도구 대기시간을 측정해 20분 판정에 여유가 있는지 확인**

사양의 성공 판정은 "초5 학생이 어른 도움 없이 **20분 안에**" 다.
그 20분에는 학생이 읽고 생각하고 타이핑하는 시간이 대부분 들어간다.
따라서 **도구가 기다리게 만드는 시간의 합이 8분을 넘으면 안 된다.**
(모델 응답 실측 13~16초 × 대화 횟수 + 그림 생성 시간)

Run:
```bash
S=$(date +%s)
CAMP_E2E=1 bash tests/test-e2e-scenario.sh
E=$(date +%s)
echo "도구 대기시간 합계: $((E-S))초 (480초 이하여야 함)"
```
Expected: 480초(8분) 이하.

초과하면 다음 순서로 줄인다:
1. `AGENTS.md` 의 "한 번에 보내는 답은 5줄 이내" 를 강화해 응답을 짧게 만든다
2. `도우미` 가 subagent 를 부르는 횟수를 줄인다 (간단한 일은 직접 처리)
3. 그래도 넘으면 사양 12절의 성공 판정을 "30분" 으로 조정할지 주최측과 협의한다.
   테스트를 느슨하게 바꾸는 것이 아니라 판정 기준을 바꾸는 결정이므로
   임의로 하지 않는다.

- [ ] **Step 6: 사람 눈으로 최종 확인**

Run: `cmd //c start "" "$TEAM/index.html"`
확인: 초등학생이 발표할 수 있게 보이는가 · 그림이 보이는가 · 화살표로 넘어가는가 · 실명이 없는가

- [ ] **Step 7: 커밋**

```bash
git add tests/test-e2e-scenario.sh camp-preset
git commit -m "test: 초5 시뮬레이션 E2E + 프리셋 보정

말투·금지용어·실명 미기록·주제 기록·그림 생성·슬라이드 추가·
오프라인 유지·영상 한도 차단을 한 흐름으로 검증한다."
```

---

### Task 12: 운영 문서 (사전교육 커리큘럼 · 치트시트 · 멘토 트러블슈팅)

**Files:**
- Create: `docs/운영/사전온라인교육-2시간.md`
- Create: `docs/운영/학생용-치트시트.md`
- Create: `docs/운영/멘토용-트러블슈팅.md`
- Create: `README.md`

**Interfaces:**
- Consumes: Task 8의 명령어 10종 이름, Task 10의 설치 스크립트
- Produces: 없음 (사람이 읽는 문서)

- [ ] **Step 1: 명령어 목록이 문서와 일치하는지 검증하는 테스트 작성**

`tests/test-docs.sh`:

```bash
#!/usr/bin/env bash
# 치트시트에 적힌 명령어가 실제로 존재하는지 검증한다.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tests/lib/assert.sh"

C="$REPO/docs/운영/학생용-치트시트.md"
assert_file "$C" "치트시트 존재"
assert_file "$REPO/docs/운영/사전온라인교육-2시간.md" "사전교육 커리큘럼 존재"
assert_file "$REPO/docs/운영/멘토용-트러블슈팅.md" "멘토용 문서 존재"
assert_file "$REPO/README.md" "README 존재"

# 치트시트가 언급한 모든 /명령어가 실제로 있어야 한다
for c in $(grep -oE '/[가-힣]+' "$C" 2>/dev/null | sort -u | tr -d '/'); do
  if [ -f "$REPO/camp-preset/command/$c.md" ]; then
    pass "치트시트 명령어 존재: /$c"
  else
    fail "치트시트에 있으나 구현 없음: /$c"
  fi
done

summary
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-docs.sh`
Expected: FAIL — 문서 4개 없음

- [ ] **Step 3: 문서 작성**

`docs/운영/학생용-치트시트.md`:

```markdown
# 우리 캠페인 만들기 — 도우미 사용법

## 뭘 해야 할지 모를 때

**`/도와줘`** 라고 쓰세요. 지금 할 일을 알려 줍니다.

## 쓸 수 있는 말

| 이렇게 쓰면 | 이런 일이 생겨요 |
|---|---|
| `/도와줘` | 지금 무엇을 하면 좋은지 알려 줘요 |
| `/시작` | 조 번호, 팀 이름, 캠페인 주제를 정해요 |
| `/아이디어` | 어떤 캠페인을 할지 같이 생각해요 |
| `/포스터` | 그림을 만들어 줘요 |
| `/음악` | 배경음악이나 로고송을 만들어 줘요 |
| `/영상` | 짧은 영상을 만들어 줘요 (팀마다 2번만!) |
| `/슬라이드추가` | 발표자료에 새 장을 넣어요 |
| `/보여줘` | 지금까지 만든 발표자료를 열어서 봐요 |
| `/발표연습` | 발표 대본을 만들고 연습해요 |
| `/제출` | 다 만든 발표자료를 제출용으로 묶어요 |

## 그냥 말해도 돼요

명령어를 안 써도 됩니다. 이렇게 그냥 말해도 알아들어요.

- "바다에 쓰레기 떠 있는 그림 만들어 줘"
- "세 번째 장 글씨 좀 줄여 줘"
- "발표자료 색을 초록색으로 바꿔 줘"

## 발표자료 넘기기

발표자료가 열리면 **→ 키**를 눌러 다음 장으로, **← 키**를 눌러 앞 장으로.

## 알아두면 좋아요

- 답이 나오는 데 **15초쯤** 걸려요. 기다려 주세요.
- 그림은 마음에 안 들면 **몇 번이든 다시** 만들 수 있어요.
- 영상은 **팀마다 2번**만 만들 수 있어요. 아껄 것!
- 발표자료에는 **이름 대신 팀 이름**을 넣어요.

---

**막히면 손을 들어 멘토 선생님을 불러요!**
```

`docs/운영/사전온라인교육-2시간.md`:

```markdown
# 사전 온라인교육 진행안 (2시간)

일정: 2026-09-14(월) ~ 09-18(금) 중 2시간 · 진행: 코드코리아
대상: 초5 20명 / 초6 20명 / 중1 20명 (총 60명)

**이 2시간의 가장 중요한 목표는 "캠프 당일 설치 사고를 0으로 만드는 것"이다.**
도구를 잘 가르치는 것보다 60대 전부에서 도구가 켜지는 것이 우선이다.

## 0:00 ~ 0:30 설치

1. 배포판 인스톨러 실행 (관리자 권한 필요 여부를 미리 안내)
2. 설치 끝에 나오는 **자체 점검 화면**에서 초록불 3개 확인
   - 인터넷 연결
   - AI 도우미 연결
   - 그림 만들기 연결
3. 초록불이 아닌 학생은 화면을 캡처해 채팅으로 보내게 한다

**안 될 때**: 백신이 막는 경우가 가장 많다. 설치 폴더를 예외로 추가한다.
그래도 안 되면 그 학생은 캠프 당일 USB 로 재설치 대상으로 명단에 올린다.

## 0:30 ~ 1:00 도우미와 인사하기

1. 바탕화면 아이콘 실행 → 조 번호와 팀 이름을 아무거나 입력해 연습 폴더 만들기
   (실제 팀 배정은 캠프 당일이므로 여기서는 연습용)
2. `/도와줘` 를 쳐 보게 한다
3. `/보여줘` 로 빈 발표자료를 열어 → ← 로 넘겨 보게 한다

**여기서 반드시 알려줄 것**: 답이 오는 데 15초쯤 걸린다. 기다려야 한다.
아이들이 여러 번 엔터를 치는 것을 막아야 한다.

## 1:00 ~ 1:30 그림 만들어 보기

`/포스터` 로 각자 그림 한 장을 만들어 본다.

**크레딧 예산**: 1인 1장 = 60크레딧. 1인 2장까지 허용하면 120크레딧.
잔액을 보고 진행 중에 조절한다. 잔액 확인: `higgsfield account status`

**안 될 때**: 잔액 소진이면 그 자리에서 중단하고 시연으로 대체한다.
아이들에게는 "지금은 선생님 화면으로 같이 보자" 고 안내한다.

## 1:30 ~ 2:00 미니 실습

슬라이드 2장짜리 아주 작은 캠페인을 만들어 본다.
표지 + 만든 그림 한 장. 그 이상은 하지 않는다.

목표는 완성이 아니라 **"이 도구로 뭔가 만들어졌다" 는 경험**이다.
캠프 당일 백지에서 시작하지 않게 하는 것이 이 30분의 목적이다.

## 마치기 전 반드시

- 설치 실패자 명단 확정 (캠프 당일 USB 구제 대상)
- 학생들에게 치트시트 A4 를 파일로 배포 (당일에도 종이로 배부)
- 크레딧 잔액 기록. 캠프 예산에서 차감해 남은 예산을 다시 계산
```

`docs/운영/멘토용-트러블슈팅.md`:

```markdown
# 멘토용 트러블슈팅

캠프 당일 멘토가 손에 들고 있을 한 장. 위에서부터 자주 생기는 순서다.

| 증상 | 원인 | 조치 |
|---|---|---|
| 답이 안 옴 (15초 이상) | 정상. 모델 응답이 13~16초 | "조금만 기다려 보자" 고 안내. 엔터를 여러 번 치지 않게 한다 |
| 화면에 □□□ 가 보임 | 글꼴 미설치 | 배포판의 글꼴을 설치하고 도구를 다시 켠다 |
| 그림이 안 만들어짐 | 크레딧 소진 또는 네트워크 | `higgsfield account status` 로 잔액 확인. 소진이면 주최측에 즉시 알린다 |
| "영상은 2번까지" 라고 나옴 | 정상 동작 (팀당 한도) | 이미 만든 영상을 발표자료에서 더 크게·더 멋있게 쓰도록 유도 |
| "표지 그림은 이미 다 만들었어요" | 정상 동작 (대표 이미지 2회 한도) | 일반 그림(`/포스터`)은 무제한이라고 안내 |
| 발표자료가 안 열림 | 브라우저 기본앱 미설정 | 팀 폴더의 `index.html` 을 더블클릭하게 한다 |
| 그림이 발표자료에 안 보임 | 파일이 `assets` 밖에 있거나 절대경로 | "그림을 다시 넣어 줘" 라고 도우미에게 말하게 한다 |
| 도구가 이상한 말을 함 / 설정이 깨짐 | 설정 파손 | `install-preset.sh --force` 로 재설치 (기존 설정은 자동 백업됨) |
| 아이가 자기 이름을 넣으려 함 | 개인정보 규칙 | 도우미가 팀 이름으로 바꾼다. 멘토도 "팀 이름이 더 멋있어" 로 지원 |
| 아이가 캠프와 관계없는 걸 시킴 | 정상 (도우미가 되돌림) | 개입 불필요. 계속되면 캠페인 주제로 관심을 돌린다 |
| 발표 직전인데 완성이 안 됨 | 시간 부족 | `/발표연습` 으로 지금 있는 것만으로 대본을 만든다. 빈 장은 지운다 |

## 절대 하지 말 것

- 아이 노트북에서 멘토가 직접 타이핑해 대신 만들어 주기
  (아이 산출물이 아니게 된다. 말로 안내한다)
- 크레딧을 아끼려고 그림 만들기를 막기
  (일반 그림은 1크레딧이라 마음껏 써도 된다. 아껄 것은 영상뿐)

## 주최측에 즉시 알려야 하는 상황

- 크레딧 잔액이 200 이하로 떨어졌다
- 같은 증상이 3팀 이상에서 동시에 발생한다
- 도구가 부적절한 그림이나 문장을 만들어 냈다
```

`README.md`:

```markdown
# 창의디자인캠프 opencode 개조판

2026 영남·제주권역 창의디자인캠프(2026-09-19~20) 참가 학생 60명
(초5~중1)을 위한 opencode 캠프 전용 프리셋.

주제는 **디자인씽킹 × 생성형 AI**, 산출물은 **과학 캠페인 웹슬라이드
발표자료** 다. 학생은 코드를 보지 않고 한국어 대화만으로 발표자료를 만든다.

opencode 소스를 포크하지 않는다. 설정·에이전트·명령어·스킬 층만 쓴다.

## 구성

| 디렉토리 | 내용 |
|---|---|
| `camp-preset/` | opencode 설정 프리셋 (`~/.config/opencode/` 로 설치됨) |
| `template/` | 팀별 발표자료 템플릿 |
| `scripts/` | 미디어 래퍼 · 팀 폴더 생성 · 프리셋 설치 |
| `tests/` | 검증 스크립트 |
| `docs/운영/` | 사전교육 진행안 · 학생 치트시트 · 멘토 트러블슈팅 |

## 설치

```bash
bash scripts/install-preset.sh
```

기존 설정이 있으면 거부한다. 덮어쓰려면 `--force` (자동 백업됨).

## 팀 폴더 만들기

```bash
bash scripts/new-team.sh 3 지구지킴이
```

## 테스트

```bash
bash tests/run-all.sh                  # 크레딧을 쓰지 않는 테스트 전체
CAMP_E2E=1 bash tests/run-all.sh       # 실제 API 호출 포함 (크레딧 소모)
```

테스트는 `OPENCODE_CONFIG_DIR` 로 격리되어 개발자의 실제 opencode
설정을 건드리지 않는다.

## 문서

- 설계: `docs/superpowers/specs/2026-08-21-camp-opencode-preset-design.md`
- 구현 계획: `docs/superpowers/plans/2026-08-21-camp-opencode-preset.md`
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-docs.sh`
Expected: PASS — 치트시트의 모든 명령어가 실재

- [ ] **Step 5: 전체 테스트**

Run: `bash tests/run-all.sh`
Expected: PASS — 전체 통과

- [ ] **Step 6: 커밋**

```bash
git add docs/운영 README.md tests/test-docs.sh
git commit -m "docs: 운영 문서 3종 + README

사전 온라인교육 2시간 커리큘럼, 학생용 치트시트 A4 1장,
멘토용 트러블슈팅 표. 치트시트의 명령어가 실재하는지 테스트로 검증."
```

---

## 남은 검증 (이 계획 밖, 사양 9절)

구현이 끝난 뒤 별도로 확인해야 하는 것들:

1. **한글 사용자명 경로** — Windows 사용자명이 한글인 노트북에서 프리셋이 동작하는지. 실기기 필요
2. **Nerd Font 없을 때 깨짐 정도** — 인스톨러가 폰트를 반드시 넣어야 하는지 판단
3. **60명 동시 사용** — DeepSeek·Higgsfield 동시성. W3 부하 테스트
4. **크레딧 충전** — 주최측 결제 건. 현재 잔액 1,360, 캠프 예산 추정 1,106 + 사전교육 60 → 최소 2,500 권고
5. **`%ProgramData%\opencode` 관리자 설정** — 학생이 프리셋을 깨뜨리는 것을 막는 데 유용. 문서화 안 됨, 소스 확인 필요
6. **`permission.bash` 패턴 허용** — 현재 `bash: "allow"` 로 두었다. 명령 단위 제한이 가능하면 좁힌다

## 다음 단계 (이 계획 완료 후)

- Windows 인스톨러 (opencode 1.18.20 + Node LTS + Git + VS Code + ripgrep + Nerd Font + 프리셋 + DeepSeek `auth.json` + Higgsfield `credentials.json`/`config.json` + 자체 점검 화면)
- 학생용 런처 (팀 정보 입력 → `new-team.sh` 호출 → opencode 실행 → 보기/제출 버튼)
- 자체 서브도메인 정적 배포
- 자체 Git 호스팅 (다음 회차)
