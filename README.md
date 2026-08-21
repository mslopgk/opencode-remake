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
설정을 건드리지 않는다. 단위 테스트는 mock `higgsfield` 를 써서
크레딧을 쓰지 않는다.

## 비용 통제

크레딧 예산은 프롬프트가 아니라 `scripts/camp-media.sh` 가 강제한다.

| 용도 | 모델 | 크레딧 | 제한 |
|---|---|---|---|
| 반복 이미지 | `nano_banana_2_lite` | 1 | 없음 |
| 최종 대표 이미지 | `gpt_image_2` | 7 | 팀당 2회 |
| 오디오·음악 | `seed_audio` | 0.1 | 없음 |
| 영상 | `seedance_2_0` | 22.5 | 팀당 2회 |

## 문서

- 설계: `docs/superpowers/specs/2026-08-21-camp-opencode-preset-design.md`
- 구현 계획: `docs/superpowers/plans/2026-08-21-camp-opencode-preset.md`
