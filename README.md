# 창의디자인캠프 opencode 개조판

2026 영남·제주권역 창의디자인캠프(2026-09-19~20) 참가 학생 60명
(초5~중1)을 위한 opencode 캠프 전용 배포판.

주제는 **디자인씽킹 × 생성형 AI**, 산출물은 **과학 캠페인 웹슬라이드
발표자료** 다. 학생은 코드를 보지 않고 한국어 대화만으로 발표자료를 만든다.

opencode 소스를 포크하지 않는다. 설정·에이전트·명령어·스킬 층만 쓴다.

## 학생이 하는 일

1. `설치하기` 더블클릭 (사전 온라인교육 때, 5~10분)
2. 캠프 당일 `캠프시작` 더블클릭 → 조 번호·팀 이름 입력
3. 데스크탑 앱이 열리면 `/시작` 이라고 쓰면 끝

## 구성

| 디렉토리 | 내용 |
|---|---|
| `camp-preset/` | opencode 설정 프리셋 (에이전트 4 · 명령어 11 · 스킬 4) |
| `template/` | 팀별 발표자료 템플릿 (웹슬라이드 + `slides/` 분리 구조) |
| `scripts/` | 미디어 래퍼 · 팀 폴더 생성 · 프리셋 설치 · 배포판 빌드 |
| `dist/` | 학생에게 전달되는 배포판 (진입점 3개 + PowerShell 스크립트) |
| `tests/` | 검증 (bash 211 어서션 + PowerShell 154 어서션) |
| `docs/운영/` | 사전교육 진행안 · 학생 치트시트 · 멘토 트러블슈팅 |
| `docs/superpowers/specs/` | 설계 문서 (프리셋 / 배포판) |

## 배포판 만들기 (주최측용)

```powershell
# 1) 프리셋·템플릿을 dist/ 로 복사
powershell -File scripts\build-dist.ps1

# 2) 아이콘과 진입점 exe 만들기
powershell -File scripts\make-icon.ps1
powershell -File scripts\build-exe.ps1

# 3) 구성요소 내려받기 + 코드 서명 검증 (약 350MB)
powershell -File scripts\fetch-bundle.ps1

# 4) 키 3개를 dist\secrets\ 에 직접 복사
#    auth.json (DeepSeek) / credentials.json, config.json (Higgsfield)

# 5) 완성도 검증
powershell -Command ". .\scripts\build-dist.ps1; Test-DistComplete -DistDir '.\dist'"
```

`dist/bundle/` 과 `dist/secrets/` 는 `.gitignore` 에 있다.
**키를 커밋하지 않도록 `git status` 로 확인한다.**

학생에게는 `dist/` 폴더 전체를 USB 또는 ZIP 으로 전달한다.

**프리셋이나 템플릿을 고쳤으면 `build-dist.ps1` 을 다시 돌려야 한다.**
안 그러면 학생이 옛 버전을 받는다 (실제로 겪은 실수).

## 개발자용

```bash
bash scripts/install-preset.sh          # 프리셋을 내 opencode 에 설치 (기존 것 백업)
bash scripts/new-team.sh 3 지구지킴이     # 팀 폴더 만들기
```

## 테스트

```bash
bash tests/run-all.sh                              # 크레딧을 쓰지 않는 bash 테스트
CAMP_E2E=1 bash tests/test-e2e-scenario.sh         # 실제 API 호출 (크레딧 1)
```

```powershell
powershell -File tests\run-all.ps1                 # PowerShell 테스트 (실제 설치 안 함)
powershell -File scripts\fix-ps1-bom.ps1           # .ps1 인코딩 고치기
```

bash 테스트는 `OPENCODE_CONFIG_DIR` 로 격리되어 개발자의 실제 opencode
설정을 건드리지 않는다. 단위 테스트는 mock `higgsfield` 를 써서 크레딧을 쓰지 않는다.

## 비용 통제

크레딧 예산은 프롬프트가 아니라 `scripts/camp-media.sh` 가 강제한다.

| 용도 | 모델 | 크레딧 | 제한 |
|---|---|---|---|
| 반복 이미지 | `nano_banana_2_lite` | 1 | 없음 |
| 최종 대표 이미지 | `gpt_image_2` | 7 | 팀당 2회 |
| 오디오·음악 | `seed_audio` | 0.1 | 없음 |
| 영상 | `seedance_2_0` | 22.5 | 팀당 2회 |

## Windows 함정 (실제로 겪은 것들)

이 프로젝트를 고칠 사람이 반드시 알아야 한다.

1. **`.ps1` 은 UTF-8 BOM 으로 저장한다.** PowerShell 5.1 은 BOM 없는 `.ps1` 을
   ANSI 로 읽어 한국어를 깨뜨린다. `scripts\fix-ps1-bom.ps1` 로 고친다
2. **`.cmd` 는 순수 ASCII 로만 둔다.** cmd.exe 가 UTF-8 배치 파일의 비ASCII 를
   잘못 파싱해 명령이 쪼개진다. 한국어는 PowerShell 쪽에 둔다
3. **학생에게 쓰는 파일은 BOM 없이 저장한다.** `Set-Content -Encoding utf8` 은
   BOM 을 붙인다. `Write-Utf8NoBom` 을 쓴다
4. **`Invoke-RestMethod` 를 쓰지 않는다.** charset 없는 응답을 ISO-8859-1 로
   디코딩해 한국어를 깨뜨린다. `WebClient` + `Encoding = UTF8` 을 쓴다
5. **함수가 컬렉션을 반환하면 쉼표로 감싼다.** PowerShell 은 반환된 컬렉션을
   파이프라인에서 풀어헤친다(unroll). 빈 `Queue` 를 그냥 `return` 하면 호출한
   쪽이 `$null` 을 받는다. `return ,$q` 로 쓴다
6. **`.cmd` 에서 `pause` 앞에 종료코드를 저장한다.** 안 하면 실패가 성공으로
   보고된다 (`set RC=%ERRORLEVEL%` … `exit /b %RC%`)

`tests\test-encoding.ps1` 이 1·2번을, `tests\test-gui.ps1` 이 5번을 회귀 검사한다.

## 문서

- 프리셋 설계: `docs/superpowers/specs/2026-08-21-camp-opencode-preset-design.md`
- 배포판 설계: `docs/superpowers/specs/2026-08-21-camp-installer-design.md`
- 구현 계획: `docs/superpowers/plans/`
- 실기기 E2E 결과: `tests/E2E-체크리스트.md`
