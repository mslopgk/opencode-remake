# 창의디자인캠프 Windows 배포판 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 초5 학생이 혼자 인스톨러를 더블클릭해 초록불 4개까지 도달하고, 캠프 당일 런처로 팀 폴더를 만들어 데스크탑 앱에서 바로 `/시작` 을 입력할 수 있게 한다.

**Architecture:** `.cmd` 진입점 3개가 PowerShell 스크립트를 호출한다. 설치는 공식 서명된 인스톨러들을 조용히 순차 실행하는 오케스트레이터이고, 프리셋·키는 파일 배치다. 데스크탑 앱의 프로젝트 등록부와 온보딩 플래그가 평문 JSON이므로 팀 폴더를 미리 등록해 학생이 폴더를 고르지 않게 한다. 자체 점검은 `opencode serve` 의 `/agent`·`/command` 를 세어 프리셋 로드를 숫자로 확정한다.

**Tech Stack:** Windows PowerShell 5.1 · `.cmd` 배치 · opencode 데스크탑 1.18.20 · 순수 PowerShell 어서션 헬퍼 (Pester 미사용)

**Spec:** `docs/superpowers/specs/2026-08-21-camp-installer-design.md`
(프리셋 선행 문서: `docs/superpowers/specs/2026-08-21-camp-opencode-preset-design.md`)

## Global Constraints

- **Windows PowerShell 5.1 전용.** `pwsh` 는 학생 노트북에 없다. 삼항연산자(`? :`),
  `??`, `?.`, `ConvertFrom-Json -AsHashtable` 을 쓰지 않는다. `if/else` 와
  명시적 `$null -eq` 비교를 쓴다
- **파일 쓰기는 인코딩을 명시한다.** `Set-Content`/`Add-Content` 는 기본이 ANSI 이므로
  한국어가 깨진다. 반드시 `-Encoding utf8`
- **네이티브 exe 에 `2>&1` 을 붙이지 않는다.** 5.1 에서 NativeCommandError 로 감싸져
  exit 0 인데도 `$?` 가 `$false` 가 된다
- **전 구성요소 per-user 설치.** 관리자 권한을 요구하면 실패로 간주한다
  (`ALLUSERS=0`, `InstallAllUsers=0`, 글꼴은 HKCU)
- **opencode 버전 고정**: `1.18.20`. 데스크탑 앱 자산은 `opencode-desktop-win-x64.exe`
- **학생 대면 텍스트는 전부 한국어.** 학생 이름·학교를 묻지 않는다
- **팀 식별자는 `NN조_팀명`** (조번호 두 자리, 1~15). `scripts/new-team.sh` 와
  동일 규칙을 유지한다
- **멱등성**: 모든 스크립트는 두 번 실행해도 안전해야 한다
- **테스트는 실제 설치를 하지 않는다.** `-DryRun` 과 임시 `APPDATA` 리다이렉트로
  검증하고, 실제 설치는 Task 10 의 실기기 E2E 한 번만

## File Structure

```
dist/                              # 배포판 (USB/ZIP 로 그대로 나감)
├─ 설치하기.cmd                    # 학생용 진입점
├─ 점검하기.cmd                    # 멘토용 재점검
├─ 캠프시작.cmd                    # 당일 런처 진입점
├─ scripts/
│  ├─ lib-assert.ps1               # 테스트용 어서션 (테스트에서만 dot-source)
│  ├─ lib-log.ps1                  # 한국어 로그 출력 + 파일 기록
│  ├─ lib-appstate.ps1             # 데스크탑 앱 JSON 상태 읽기/쓰기
│  ├─ lib-team.ps1                 # 팀 폴더 생성 (조번호 정규화·치환)
│  ├─ orchestrator.ps1             # 설치 순서 (-DryRun 지원)
│  ├─ selfcheck.ps1                # 자체 점검 4종
│  └─ launcher.ps1                 # 팀 폴더 + 앱 등록 + 앱 실행
├─ bundle/                         # 구성요소 (git 에 넣지 않는다)
├─ preset/                         # camp-preset 사본 (빌드 시 복사)
├─ template/                       # template 사본 (빌드 시 복사)
└─ secrets/                        # 키 (git 에 넣지 않는다)

scripts/
├─ fetch-bundle.ps1                # bundle/ 구성요소 내려받기 + 서명 검증
└─ build-dist.ps1                  # preset/·template/ 복사해 dist 완성

tests/
├─ run-all.ps1                     # PowerShell 테스트 러너
├─ test-appstate.ps1
├─ test-team.ps1
├─ test-orchestrator-dryrun.ps1
├─ test-selfcheck.ps1
└─ test-launcher.ps1
```

`bundle/` 과 `secrets/` 는 `.gitignore` 에 넣는다. 121MB 인스톨러와 API 키를
저장소에 커밋하지 않는다.

---

### Task 1: PowerShell 테스트 하네스 · 로그 · 배포판 골격

**Files:**
- Create: `dist/scripts/lib-assert.ps1`
- Create: `dist/scripts/lib-log.ps1`
- Create: `tests/run-all.ps1`
- Create: `tests/test-log.ps1`
- Modify: `.gitignore` (신규 생성)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `lib-assert.ps1`: `Assert-Eq $actual $expected $msg`, `Assert-True $cond $msg`,
    `Assert-Contains $haystack $needle $msg`, `Assert-NotContains`, `Assert-FileExists $path $msg`,
    `Test-Summary` (실패 0이면 `$true`). 카운터는 스크립트 스코프 `$script:Pass`/`$script:Fail`
  - `lib-log.ps1`: `Write-Step $msg` (진행 단계), `Write-Ok $msg`, `Write-Fail $msg`,
    `Write-Note $msg`, `Start-CampLog $path` / `Stop-CampLog`. 모든 출력은 한국어이며
    로그 파일에도 같은 내용이 UTF-8 로 기록된다
  - `tests/run-all.ps1`: `tests/test-*.ps1` 을 모두 실행, 하나라도 실패하면 exit 1

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-log.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"

$tmp = Join-Path $env:TEMP ("camptest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $logPath = Join-Path $tmp 'log.txt'
    Start-CampLog $logPath

    Write-Step '설치를 시작합니다'
    Write-Ok '노드를 설치했어요'
    Write-Fail '그림 만들기 연결에 실패했어요'
    Write-Note '자세한 내용은 기록 파일을 보세요'

    Stop-CampLog

    Assert-FileExists $logPath '로그 파일이 만들어짐'
    $content = Get-Content -Path $logPath -Raw -Encoding UTF8
    Assert-Contains $content '설치를 시작합니다' '단계 로그가 기록됨'
    Assert-Contains $content '노드를 설치했어요' '성공 로그가 기록됨'
    Assert-Contains $content '그림 만들기 연결에 실패했어요' '실패 로그가 기록됨'
    Assert-Contains $content '자세한 내용은' '안내 로그가 기록됨'

    # 한국어가 깨지지 않아야 한다 (ANSI 로 쓰면 물음표가 된다)
    Assert-NotContains $content '?' '한국어가 깨지지 않음'

    # 두 번 시작해도 안전 (멱등)
    Start-CampLog $logPath
    Write-Ok '두 번째 기록'
    Stop-CampLog
    $content2 = Get-Content -Path $logPath -Raw -Encoding UTF8
    Assert-Contains $content2 '두 번째 기록' '재시작 후에도 기록됨'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-log.ps1`
Expected: FAIL — `lib-assert.ps1` 을 찾을 수 없어 dot-source 단계에서 종료

- [ ] **Step 3: 어서션 헬퍼와 로그 구현**

`dist/scripts/lib-assert.ps1`:

```powershell
# 테스트용 어서션. Pester 를 쓰지 않는다 (학생 환경에는 Pester 3.4 뿐이고
# 리포의 bash 테스트와 같은 결을 유지한다).
$script:Pass = 0
$script:Fail = 0

function Assert-Pass([string]$Msg) {
    $script:Pass++
    Write-Host ("  ok   " + $Msg)
}

function Assert-Failure([string]$Msg) {
    $script:Fail++
    Write-Host ("  FAIL " + $Msg) -ForegroundColor Red
}

function Assert-Eq($Actual, $Expected, [string]$Msg) {
    if ($Actual -eq $Expected) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg (기대='$Expected' 실제='$Actual')") }
}

function Assert-True($Condition, [string]$Msg) {
    if ($Condition) { Assert-Pass $Msg } else { Assert-Failure $Msg }
}

function Assert-Contains([string]$Haystack, [string]$Needle, [string]$Msg) {
    if ($null -ne $Haystack -and $Haystack.Contains($Needle)) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg ('$Needle' 없음)") }
}

function Assert-NotContains([string]$Haystack, [string]$Needle, [string]$Msg) {
    if ($null -eq $Haystack -or -not $Haystack.Contains($Needle)) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg ('$Needle' 가 있으면 안 됨)") }
}

function Assert-FileExists([string]$Path, [string]$Msg) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg (파일 없음: $Path)") }
}

function Test-Summary {
    Write-Host ""
    Write-Host ("{0}: {1} passed, {2} failed" -f (Split-Path -Leaf $MyInvocation.ScriptName), $script:Pass, $script:Fail)
    return ($script:Fail -eq 0)
}
```

`dist/scripts/lib-log.ps1`:

```powershell
# 학생·멘토가 읽는 한국어 로그. 화면과 파일에 동시에 남긴다.
$script:CampLogPath = $null

function Start-CampLog([string]$Path) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $script:CampLogPath = $Path
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Path -Value ("===== 기록 시작 " + $stamp + " =====") -Encoding utf8
}

function Stop-CampLog {
    if ($null -ne $script:CampLogPath) {
        Add-Content -LiteralPath $script:CampLogPath -Value "===== 기록 끝 =====" -Encoding utf8
    }
    $script:CampLogPath = $null
}

function Write-CampLine([string]$Line, [string]$Color) {
    if ($Color) { Write-Host $Line -ForegroundColor $Color } else { Write-Host $Line }
    if ($null -ne $script:CampLogPath) {
        Add-Content -LiteralPath $script:CampLogPath -Value $Line -Encoding utf8
    }
}

function Write-Step([string]$Msg) { Write-CampLine ("[진행] " + $Msg) 'Cyan' }
function Write-Ok([string]$Msg)   { Write-CampLine ("[완료] " + $Msg) 'Green' }
function Write-Fail([string]$Msg) { Write-CampLine ("[실패] " + $Msg) 'Red' }
function Write-Note([string]$Msg) { Write-CampLine ("[안내] " + $Msg) 'Yellow' }
```

`tests/run-all.ps1`:

```powershell
$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rc = 0
Get-ChildItem -Path (Join-Path $Repo 'tests') -Filter 'test-*.ps1' | ForEach-Object {
    Write-Host ""
    Write-Host ("=== " + $_.Name + " ===")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { $rc = 1 }
}
Write-Host ""
if ($rc -eq 0) { Write-Host "전체 통과" } else { Write-Host "실패 있음" -ForegroundColor Red }
exit $rc
```

`.gitignore` (저장소 최상위, 신규):

```
# 배포판 구성요소 — 121MB 인스톨러 등은 커밋하지 않는다
dist/bundle/
# API 키 — 절대 커밋하지 않는다
dist/secrets/
# 빌드 시 복사되는 사본
dist/preset/
dist/template/
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-log.ps1`
Expected: PASS — `0 failed`. 특히 "한국어가 깨지지 않음" 이 통과해야 한다
(`-Encoding utf8` 을 빼면 여기서 실패한다)

- [ ] **Step 5: 커밋**

```bash
git add dist/scripts/lib-assert.ps1 dist/scripts/lib-log.ps1 tests/run-all.ps1 tests/test-log.ps1 .gitignore
git commit -m "test: PowerShell 테스트 하네스와 한국어 로그

Pester 대신 순수 PowerShell 어서션을 쓴다(학생 환경은 5.1 + Pester 3.4).
로그는 화면과 파일에 UTF-8 로 동시에 남긴다 — Set-Content 기본 ANSI 로는
한국어가 깨지므로 -Encoding utf8 을 강제한다."
```

---

### Task 2: 데스크탑 앱 상태 조작 (`lib-appstate.ps1`)

실측으로 확인된 평문 JSON 두 파일을 다룬다. 학생이 폴더를 고르지 않게 하는
핵심 코드다.

**Files:**
- Create: `dist/scripts/lib-appstate.ps1`
- Create: `tests/test-appstate.ps1`

**Interfaces:**
- Consumes: Task 1의 `lib-assert.ps1`
- Produces:
  - `Get-AppStateDir` — `$env:APPDATA\ai.opencode.desktop` 경로 반환.
    테스트는 `$env:CAMP_APPSTATE_DIR` 로 덮어쓸 수 있다
  - `Get-RegisteredProjects` → 등록된 worktree 경로 문자열 배열 (없으면 빈 배열)
  - `Add-RegisteredProject -Path <경로>` → 등록부에 추가. 이미 있으면 아무 것도 안 함.
    `$true` 반환 시 성공
  - `Set-OnboardingComplete` → `opencode.settings` 의
    `firstLaunchOnboardingComplete` 를 `$true` 로
  - 실측 구조: `opencode.global.dat` 는 최상위 JSON 객체이고 `server` 키의 **값이
    JSON 문자열**이다. 그 문자열을 파싱하면 `{"list":[],"projects":{"local":[{"worktree":"..."}]}}`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-appstate.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"

$tmp = Join-Path $env:TEMP ("campstate-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$env:CAMP_APPSTATE_DIR = $tmp
try {
    # --- 1) 상태 파일이 아예 없는 새 노트북 ---
    Assert-Eq (Get-RegisteredProjects).Count 0 '상태 파일이 없으면 빈 목록'

    $ok = Add-RegisteredProject -Path 'C:\창의디자인캠프\연습'
    Assert-True $ok '상태 파일이 없어도 등록 성공'
    $projects = Get-RegisteredProjects
    Assert-Eq $projects.Count 1 '등록 후 1개'
    Assert-Eq $projects[0] 'C:\창의디자인캠프\연습' '등록된 경로가 일치'

    # --- 2) 중복 등록은 늘어나지 않는다 (멱등) ---
    Add-RegisteredProject -Path 'C:\창의디자인캠프\연습' | Out-Null
    Assert-Eq (Get-RegisteredProjects).Count 1 '같은 경로 재등록은 무시'

    # --- 3) 두 번째 팀 폴더 추가 ---
    Add-RegisteredProject -Path 'C:\창의디자인캠프\03조_지구지킴이' | Out-Null
    Assert-Eq (Get-RegisteredProjects).Count 2 '다른 경로는 추가됨'

    # --- 4) 기존 앱 상태(실측 형태)를 깨지 않는다 ---
    $existing = @{
        'notification' = '{"list":[]}'
        'server' = '{"list":[],"projects":{"local":[{"worktree":"C:\\Users\\user\\Documents\\Default Project","expanded":true}]}}'
        'model' = '{"user":[{"modelID":"deepseek-v4-flash","providerID":"deepseek"}]}'
    }
    $globalPath = Join-Path $tmp 'opencode.global.dat'
    ($existing | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $globalPath -Encoding utf8

    Add-RegisteredProject -Path 'C:\창의디자인캠프\07조_별빛' | Out-Null
    $after = Get-RegisteredProjects
    Assert-True ($after -contains 'C:\Users\user\Documents\Default Project') '기존 프로젝트가 보존됨'
    Assert-True ($after -contains 'C:\창의디자인캠프\07조_별빛') '새 프로젝트가 추가됨'

    $raw = Get-Content -LiteralPath $globalPath -Raw -Encoding UTF8
    Assert-Contains $raw 'deepseek-v4-flash' '다른 키(model)가 보존됨'
    Assert-Contains $raw 'notification' '다른 키(notification)가 보존됨'

    # --- 5) 온보딩 건너뛰기 ---
    Set-OnboardingComplete
    $settings = Get-Content -LiteralPath (Join-Path $tmp 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings.firstLaunchOnboardingComplete $true '온보딩 완료 플래그가 설정됨'

    # --- 6) 기존 settings 의 다른 키를 보존한다 ---
    Assert-True $true '기존 키 보존 검사 준비'
    $s = @{ 'windowIds' = @('abc-123'); 'tauriMigrated' = $true }
    ($s | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $tmp 'opencode.settings') -Encoding utf8
    Set-OnboardingComplete
    $settings2 = Get-Content -LiteralPath (Join-Path $tmp 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings2.firstLaunchOnboardingComplete $true '재설정 후에도 플래그가 참'
    Assert-Eq $settings2.windowIds[0] 'abc-123' '기존 windowIds 가 보존됨'

    # --- 7) 손상된 JSON 은 앱을 망가뜨리지 않고 실패를 알린다 ---
    'this is not json' | Set-Content -LiteralPath $globalPath -Encoding utf8
    $ok2 = Add-RegisteredProject -Path 'C:\창의디자인캠프\09조_바다'
    Assert-Eq $ok2 $false '손상된 상태 파일에서는 false 반환'
    $rawBroken = Get-Content -LiteralPath $globalPath -Raw -Encoding UTF8
    Assert-Contains $rawBroken 'this is not json' '손상된 파일을 덮어쓰지 않음'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-appstate.ps1`
Expected: FAIL — `lib-appstate.ps1` 없음

- [ ] **Step 3: 구현**

`dist/scripts/lib-appstate.ps1`:

```powershell
# opencode 데스크탑 앱의 상태 파일을 다룬다.
#
# 실측(2026-08-21, v1.18.20)으로 확인한 구조:
#   %APPDATA%\ai.opencode.desktop\opencode.global.dat
#     → 최상위 JSON 객체. "server" 키의 값이 "JSON 문자열"이고
#       그것을 파싱하면 {"list":[],"projects":{"local":[{"worktree":"..."}]}}
#   %APPDATA%\ai.opencode.desktop\opencode.settings
#     → 최상위 JSON 객체. firstLaunchOnboardingComplete 로 온보딩을 건너뛴다
#
# 손상된 파일은 절대 덮어쓰지 않는다. 앱 상태를 망가뜨리는 것이
# 등록 실패보다 훨씬 나쁘다.

function Get-AppStateDir {
    if ($env:CAMP_APPSTATE_DIR) { return $env:CAMP_APPSTATE_DIR }
    return (Join-Path $env:APPDATA 'ai.opencode.desktop')
}

function Read-JsonFile([string]$Path) {
    # 성공하면 객체, 파일이 없으면 $null, 손상되면 문자열 'BROKEN'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return 'BROKEN' }
}

function Get-ServerBlob($GlobalObj) {
    # server 키의 값(JSON 문자열)을 객체로. 없으면 기본 골격을 만든다
    if ($null -ne $GlobalObj -and $GlobalObj.PSObject.Properties.Name -contains 'server') {
        try { return ($GlobalObj.server | ConvertFrom-Json) } catch { return 'BROKEN' }
    }
    return ('{"list":[],"projects":{"local":[]}}' | ConvertFrom-Json)
}

function Get-RegisteredProjects {
    $path = Join-Path (Get-AppStateDir) 'opencode.global.dat'
    $g = Read-JsonFile $path
    if ($g -is [string]) { return @() }          # 손상
    $server = Get-ServerBlob $g
    if ($server -is [string]) { return @() }     # 손상
    $out = @()
    if ($null -ne $server.projects -and $null -ne $server.projects.local) {
        foreach ($p in @($server.projects.local)) {
            if ($null -ne $p -and $p.worktree) { $out += [string]$p.worktree }
        }
    }
    return $out
}

function Add-RegisteredProject([Parameter(Mandatory=$true)][string]$Path) {
    $dir = Get-AppStateDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $file = Join-Path $dir 'opencode.global.dat'

    $g = Read-JsonFile $file
    if ($g -is [string]) { return $false }       # 손상 — 덮어쓰지 않는다
    if ($null -eq $g) { $g = ('{}' | ConvertFrom-Json) }

    $server = Get-ServerBlob $g
    if ($server -is [string]) { return $false }

    if ($null -eq $server.projects) {
        $server | Add-Member -NotePropertyName 'projects' -NotePropertyValue ('{"local":[]}' | ConvertFrom-Json) -Force
    }
    if ($null -eq $server.projects.local) {
        $server.projects | Add-Member -NotePropertyName 'local' -NotePropertyValue @() -Force
    }

    $existing = @()
    foreach ($p in @($server.projects.local)) {
        if ($null -ne $p -and $p.worktree) { $existing += [string]$p.worktree }
    }
    if ($existing -contains $Path) { return $true }   # 이미 있음 — 멱등

    $entry = New-Object psobject
    $entry | Add-Member -NotePropertyName 'worktree' -NotePropertyValue $Path
    $entry | Add-Member -NotePropertyName 'expanded' -NotePropertyValue $true
    $server.projects.local = @($server.projects.local) + @($entry)

    $g | Add-Member -NotePropertyName 'server' -NotePropertyValue ($server | ConvertTo-Json -Depth 20 -Compress) -Force
    ($g | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $file -Encoding utf8
    return $true
}

function Set-OnboardingComplete {
    $dir = Get-AppStateDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $file = Join-Path $dir 'opencode.settings'

    $s = Read-JsonFile $file
    if ($s -is [string]) { return $false }       # 손상 — 덮어쓰지 않는다
    if ($null -eq $s) { $s = ('{}' | ConvertFrom-Json) }

    $s | Add-Member -NotePropertyName 'firstLaunchOnboardingComplete' -NotePropertyValue $true -Force
    ($s | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $file -Encoding utf8
    return $true
}
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-appstate.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: 실제 앱 상태를 읽어 형식 가정을 재확인 (읽기만)**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\dist\scripts\lib-appstate.ps1; Get-RegisteredProjects"
```
Expected: 이 PC 에 실제 등록된 프로젝트 경로가 출력된다
(최소 `C:\Users\user\Documents\Default Project`). 아무 것도 안 나오면
`server` 키 구조 가정이 틀렸다는 뜻이므로 실제 파일을 다시 확인한다.
**이 단계는 읽기만 한다. 개발자의 앱 상태를 수정하지 않는다.**

- [ ] **Step 6: 커밋**

```bash
git add dist/scripts/lib-appstate.ps1 tests/test-appstate.ps1
git commit -m "feat: 데스크탑 앱 상태 조작 lib-appstate.ps1

프로젝트 등록부(opencode.global.dat 의 server 키 안 JSON 문자열)와
온보딩 플래그(opencode.settings)를 다룬다. 학생이 폴더를 고르지 않게
하는 핵심 코드.

멱등하고, 다른 키를 보존하며, 손상된 JSON 은 덮어쓰지 않고 false 를
반환한다 — 앱 상태를 망가뜨리는 것이 등록 실패보다 나쁘다."
```

---

### Task 3: 팀 폴더 생성 (`lib-team.ps1`)

`scripts/new-team.sh` 와 동일한 규칙을 PowerShell 로 옮긴다. 런처는 bash 가
없는 학생 노트북에서 돌아야 한다.

**Files:**
- Create: `dist/scripts/lib-team.ps1`
- Create: `tests/test-team.ps1`

**Interfaces:**
- Consumes: Task 1의 `lib-assert.ps1`
- Produces:
  - `Get-TeamFolderName -Number <int> -Name <string>` → `'03조_지구지킴이'`.
    조번호 1~15 밖이거나 이름에 `\ / : * ? " < > |` 가 있으면 `$null`
  - `New-TeamFolder -Number <int> -Name <string> -Parent <경로> -TemplateDir <경로>`
    → 만든 폴더의 전체 경로. 이미 있으면 그 경로를 그대로 반환(멱등, 덮어쓰지 않음).
    인자가 잘못되면 `$null`
  - 치환 규칙은 `new-team.sh` 와 동일: `우리팀.md` 의
    `- 조 번호: (아직 안 정함)` / `- 팀 이름: (아직 안 정함)`,
    `index.html` 의 `00조 팀이름`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-team.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-team.ps1"

$Template = Join-Path $Repo 'template'
$tmp = Join-Path $env:TEMP ("campteam-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    # --- 이름 정규화 ---
    Assert-Eq (Get-TeamFolderName -Number 3 -Name '지구지킴이') '03조_지구지킴이' '조번호 두 자리 정규화'
    Assert-Eq (Get-TeamFolderName -Number 15 -Name '별빛') '15조_별빛' '15조 허용'
    Assert-Eq (Get-TeamFolderName -Number 0 -Name '팀') $null '0조는 거부'
    Assert-Eq (Get-TeamFolderName -Number 16 -Name '팀') $null '16조는 거부'
    Assert-Eq (Get-TeamFolderName -Number 3 -Name 'a\b') $null '경로 문자 포함은 거부'
    Assert-Eq (Get-TeamFolderName -Number 3 -Name '') $null '빈 이름은 거부'

    # --- 폴더 생성 ---
    $dir = New-TeamFolder -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template
    Assert-True ($null -ne $dir) '팀 폴더 생성 성공'
    Assert-Contains $dir '03조_지구지킴이' '경로에 팀 폴더명 포함'
    Assert-FileExists (Join-Path $dir 'index.html') 'index.html 복사됨'
    Assert-FileExists (Join-Path $dir '우리팀.md') '우리팀.md 복사됨'
    Assert-True (Test-Path -LiteralPath (Join-Path $dir 'assets') -PathType Container) 'assets 폴더 생성'

    $doc = Get-Content -LiteralPath (Join-Path $dir '우리팀.md') -Raw -Encoding UTF8
    Assert-Contains $doc '조 번호: 03조' '우리팀.md 조번호 기입'
    Assert-Contains $doc '팀 이름: 지구지킴이' '우리팀.md 팀이름 기입'
    Assert-NotContains $doc '팀 이름: (아직 안 정함)' '팀이름 자리표시자 제거'
    Assert-NotContains $doc '조 번호: (아직 안 정함)' '조번호 자리표시자 제거'

    $html = Get-Content -LiteralPath (Join-Path $dir 'index.html') -Raw -Encoding UTF8
    Assert-Contains $html '03조 지구지킴이' '표지에 조번호·팀이름 반영'
    Assert-NotContains $html '00조 팀이름' '표지 자리표시자 제거'

    # --- 멱등: 두 번째 호출은 덮어쓰지 않는다 ---
    $marker = Join-Path $dir '학생작업.txt'
    '학생이 만든 내용' | Set-Content -LiteralPath $marker -Encoding utf8
    $dir2 = New-TeamFolder -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template
    Assert-Eq $dir2 $dir '같은 팀 재호출은 같은 경로 반환'
    Assert-FileExists $marker '학생 작업물이 보존됨'

    # --- 잘못된 인자 ---
    Assert-Eq (New-TeamFolder -Number 99 -Name '팀' -Parent $tmp -TemplateDir $Template) $null '잘못된 조번호는 null'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-team.ps1`
Expected: FAIL — `lib-team.ps1` 없음

- [ ] **Step 3: 구현**

`dist/scripts/lib-team.ps1`:

```powershell
# 팀 폴더를 만든다. scripts/new-team.sh 와 규칙이 같아야 한다
# (조번호 두 자리, 1~15, NN조_팀명, 자리표시자 치환).
# 학생 노트북에는 bash 가 없으므로 PowerShell 로 따로 구현한다.

function Get-TeamFolderName([int]$Number, [string]$Name) {
    if ($Number -lt 1 -or $Number -gt 15) { return $null }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $bad = @('\', '/', ':', '*', '?', '"', '<', '>', '|')
    foreach ($ch in $bad) {
        if ($Name.Contains($ch)) { return $null }
    }
    return ('{0:D2}조_{1}' -f $Number, $Name)
}

function New-TeamFolder([int]$Number, [string]$Name, [string]$Parent, [string]$TemplateDir) {
    $folder = Get-TeamFolderName -Number $Number -Name $Name
    if ($null -eq $folder) { return $null }
    if (-not (Test-Path -LiteralPath $TemplateDir -PathType Container)) { return $null }

    if (-not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $dir = Join-Path $Parent $folder

    # 이미 있으면 절대 덮어쓰지 않는다 — 학생 작업물이 들어 있을 수 있다
    if (Test-Path -LiteralPath $dir -PathType Container) { return $dir }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $dir -Recurse -Force
    $assets = Join-Path $dir 'assets'
    if (-not (Test-Path -LiteralPath $assets)) {
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
    }

    $pad = '{0:D2}' -f $Number

    $docPath = Join-Path $dir '우리팀.md'
    if (Test-Path -LiteralPath $docPath -PathType Leaf) {
        $doc = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8
        $doc = $doc.Replace('- 조 번호: (아직 안 정함)', ('- 조 번호: ' + $pad + '조'))
        $doc = $doc.Replace('- 팀 이름: (아직 안 정함)', ('- 팀 이름: ' + $Name))
        Set-Content -LiteralPath $docPath -Value $doc -Encoding utf8 -NoNewline
    }

    $htmlPath = Join-Path $dir 'index.html'
    if (Test-Path -LiteralPath $htmlPath -PathType Leaf) {
        $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
        $html = $html.Replace('00조 팀이름', ($pad + '조 ' + $Name))
        Set-Content -LiteralPath $htmlPath -Value $html -Encoding utf8 -NoNewline
    }

    return $dir
}
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-team.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: bash 판과 결과가 같은지 교차 확인**

Run:
```bash
TMPA=$(mktemp -d); TMPB=$(mktemp -d)
bash scripts/new-team.sh 3 지구지킴이 "$TMPA" >/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\dist\scripts\lib-team.ps1; New-TeamFolder -Number 3 -Name '지구지킴이' -Parent '$(cygpath -w $TMPB)' -TemplateDir '$(cygpath -w $PWD/template)'" >/dev/null
diff -r "$TMPA/03조_지구지킴이" "$TMPB/03조_지구지킴이" && echo "bash 판과 PowerShell 판 결과 동일"
rm -rf "$TMPA" "$TMPB"
```
Expected: `결과 동일`. 차이가 나면 치환 규칙이 어긋난 것이므로 맞춘다
(개행 문자 차이만 나면 `.gitattributes` 의 `eol=lf` 때문이므로 `diff --strip-trailing-cr` 로 재확인)

- [ ] **Step 6: 커밋**

```bash
git add dist/scripts/lib-team.ps1 tests/test-team.ps1
git commit -m "feat: 팀 폴더 생성 lib-team.ps1

new-team.sh 와 동일한 규칙(조번호 두 자리, 1~15, 자리표시자 치환)을
PowerShell 로 구현한다. 학생 노트북에는 bash 가 없다.
이미 있는 팀 폴더는 절대 덮어쓰지 않는다 — 학생 작업물이 들어 있다."
```

---

### Task 4: 자체 점검 (`selfcheck.ps1`)

설치가 됐는지를 "된 것 같다"가 아니라 숫자로 확정한다.

**Files:**
- Create: `dist/scripts/selfcheck.ps1`
- Create: `tests/test-selfcheck.ps1`

**Interfaces:**
- Consumes: Task 1의 `lib-log.ps1`, `lib-assert.ps1`
- Produces:
  - `Test-OpencodeVersion -Expected '1.18.20'` → `$true`/`$false`
  - `Test-PresetLoaded -Port <int>` → `@{ Ok=$bool; Agents=<int>; Commands=<int> }`.
    `opencode serve` 를 띄워 `/agent`·`/command` 를 세고 서버를 종료한다.
    통과 조건은 에이전트 4, 명령어 10
  - `Test-DeepSeek` → `$true`/`$false` (`opencode run` 으로 한국어 응답 확인)
  - `Test-Higgsfield` → `@{ Ok=$bool; Credits=<double> }`
  - `Invoke-SelfCheck` → 네 항목을 순서대로 실행하고 초록불/빨간불 화면을
    한국어로 출력, 실패 항목의 조치 안내를 표시. 모두 통과 시 exit 0
  - 각 함수는 `$env:CAMP_SELFCHECK_FAKE` 가 설정되면 실제 호출 없이
    그 값(`ok`/`fail`)에 따라 결과를 반환한다 — 테스트용

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-selfcheck.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\selfcheck.ps1"

# 가짜 모드에서 모두 성공
$env:CAMP_SELFCHECK_FAKE = 'ok'
try {
    Assert-True (Test-OpencodeVersion -Expected '1.18.20') '가짜 모드: 버전 통과'
    $p = Test-PresetLoaded -Port 4321
    Assert-True $p.Ok '가짜 모드: 프리셋 통과'
    Assert-Eq $p.Agents 4 '가짜 모드: 에이전트 4'
    Assert-Eq $p.Commands 10 '가짜 모드: 명령어 10'
    Assert-True (Test-DeepSeek) '가짜 모드: DeepSeek 통과'
    $h = Test-Higgsfield
    Assert-True $h.Ok '가짜 모드: Higgsfield 통과'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

# 가짜 모드에서 모두 실패
$env:CAMP_SELFCHECK_FAKE = 'fail'
try {
    Assert-Eq (Test-OpencodeVersion -Expected '1.18.20') $false '가짜 모드: 버전 실패'
    Assert-Eq (Test-PresetLoaded -Port 4321).Ok $false '가짜 모드: 프리셋 실패'
    Assert-Eq (Test-DeepSeek) $false '가짜 모드: DeepSeek 실패'
    Assert-Eq (Test-Higgsfield).Ok $false '가짜 모드: Higgsfield 실패'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

# 통과 조건이 4/10 으로 고정되어 있는지 (3/10 이면 실패해야 한다)
$env:CAMP_SELFCHECK_FAKE = 'partial'
try {
    $p2 = Test-PresetLoaded -Port 4321
    Assert-Eq $p2.Ok $false '에이전트가 부족하면 실패로 판정'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-selfcheck.ps1`
Expected: FAIL — `selfcheck.ps1` 없음

- [ ] **Step 3: 구현**

`dist/scripts/selfcheck.ps1`:

```powershell
# 설치가 실제로 됐는지 확정한다.
# 핵심: 프리셋 로드를 opencode 서버 API 로 "세어서" 확인한다 (실측 검증됨).

$script:ExpectedAgents = 4
$script:ExpectedCommands = 10
$script:AgentNames = @('도우미', '아이디어', '디자이너', '미디어')
$script:CommandNames = @('시작','아이디어','포스터','음악','영상','슬라이드추가','보여줘','발표연습','제출','도와줘')

function Get-FakeMode { return $env:CAMP_SELFCHECK_FAKE }

function Test-OpencodeVersion([string]$Expected) {
    $fake = Get-FakeMode
    if ($fake) { return ($fake -eq 'ok' -or $fake -eq 'partial') }
    $exe = Get-Command opencode -ErrorAction SilentlyContinue
    if ($null -eq $exe) { return $false }
    $out = & opencode --version
    if ($LASTEXITCODE -ne 0) { return $false }
    return (([string]$out).Trim() -eq $Expected)
}

function Test-PresetLoaded([int]$Port) {
    $fake = Get-FakeMode
    if ($fake -eq 'ok')      { return @{ Ok = $true;  Agents = 4; Commands = 10 } }
    if ($fake -eq 'partial') { return @{ Ok = $false; Agents = 3; Commands = 10 } }
    if ($fake -eq 'fail')    { return @{ Ok = $false; Agents = 0; Commands = 0 } }

    $proc = Start-Process -FilePath 'opencode' `
        -ArgumentList @('serve', '--port', $Port, '--hostname', '127.0.0.1') `
        -PassThru -WindowStyle Hidden
    try {
        $base = "http://127.0.0.1:$Port"
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 700
            try {
                Invoke-RestMethod -Uri ($base + '/agent') -TimeoutSec 3 | Out-Null
                $ready = $true
                break
            } catch { }
        }
        if (-not $ready) { return @{ Ok = $false; Agents = 0; Commands = 0 } }

        $agents = Invoke-RestMethod -Uri ($base + '/agent') -TimeoutSec 10
        $commands = Invoke-RestMethod -Uri ($base + '/command') -TimeoutSec 20

        $agentNames = @()
        foreach ($a in @($agents)) { if ($a.name) { $agentNames += [string]$a.name } }
        $commandNames = @()
        foreach ($c in @($commands)) { if ($c.name) { $commandNames += [string]$c.name } }

        $na = 0
        foreach ($n in $script:AgentNames) { if ($agentNames -contains $n) { $na++ } }
        $nc = 0
        foreach ($n in $script:CommandNames) { if ($commandNames -contains $n) { $nc++ } }

        $ok = ($na -eq $script:ExpectedAgents -and $nc -eq $script:ExpectedCommands)
        return @{ Ok = $ok; Agents = $na; Commands = $nc }
    }
    finally {
        if ($null -ne $proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-DeepSeek {
    $fake = Get-FakeMode
    if ($fake) { return ($fake -eq 'ok' -or $fake -eq 'partial') }
    $out = & opencode run '안녕하세요' --agent 도우미
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = [string]::Join("`n", @($out))
    # 한국어 응답이 왔는지 (한글 음절이 하나라도 있으면 통과)
    return ($text -match '[가-힣]')
}

function Test-Higgsfield {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return @{ Ok = $true; Credits = 999.0 } }
    if ($fake -eq 'fail') { return @{ Ok = $false; Credits = 0.0 } }

    $cmd = Get-Command higgsfield -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return @{ Ok = $false; Credits = 0.0 } }
    $out = & higgsfield account status
    if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Credits = 0.0 } }
    $text = [string]::Join(' ', @($out))
    $credits = 0.0
    $m = [regex]::Match($text, '([0-9]+(\.[0-9]+)?)\s*credits')
    if ($m.Success) { $credits = [double]$m.Groups[1].Value }
    return @{ Ok = ($text -match 'credits'); Credits = $credits }
}

function Invoke-SelfCheck {
    Write-Step '설치가 잘 됐는지 확인할게요. 조금만 기다려 주세요.'
    $fails = @()

    Write-Step '1/4 도구가 깔렸는지 확인 중'
    if (Test-OpencodeVersion -Expected '1.18.20') { Write-Ok '도구가 깔렸어요' }
    else { Write-Fail '도구가 제대로 안 깔렸어요'; $fails += '도구' }

    Write-Step '2/4 캠프 설정이 들어갔는지 확인 중'
    $p = Test-PresetLoaded -Port 4399
    if ($p.Ok) { Write-Ok '캠프 설정이 들어갔어요' }
    else {
        Write-Fail ('캠프 설정이 덜 들어갔어요 (도우미 ' + $p.Agents + '/4, 명령 ' + $p.Commands + '/10)')
        $fails += '설정'
    }

    Write-Step '3/4 AI 도우미가 연결되는지 확인 중'
    if (Test-DeepSeek) { Write-Ok 'AI 도우미가 연결됐어요' }
    else { Write-Fail 'AI 도우미가 연결되지 않았어요'; $fails += 'AI' }

    Write-Step '4/4 그림 만들기가 연결되는지 확인 중'
    $h = Test-Higgsfield
    if ($h.Ok) {
        Write-Ok ('그림 만들기가 연결됐어요 (남은 양 ' + $h.Credits + ')')
        if ($h.Credits -lt 200) { Write-Note '남은 양이 적어요. 선생님께 알려 주세요.' }
    }
    else { Write-Fail '그림 만들기가 연결되지 않았어요'; $fails += '그림' }

    Write-Host ''
    if ($fails.Count -eq 0) {
        Write-Ok '준비 끝! 이제 캠프시작을 눌러서 시작하면 돼요.'
        return 0
    }

    Write-Fail ('안 된 것: ' + ($fails -join ', '))
    Write-Note '아래를 확인해 보세요.'
    if ($fails -contains '도구')  { Write-Note '- 설치하기를 다시 실행해 주세요.' }
    if ($fails -contains '설정')  { Write-Note '- 설치하기를 다시 실행하면 설정이 다시 들어갑니다.' }
    if ($fails -contains 'AI')    { Write-Note '- 인터넷이 연결됐는지 확인해 주세요.' }
    if ($fails -contains '그림')  { Write-Note '- 인터넷 확인 후에도 안 되면 선생님을 불러 주세요.' }
    Write-Note '그래도 안 되면 선생님께 기록 파일을 보여 주세요.'
    return 1
}
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-selfcheck.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: 실제 점검을 돌려 프리셋 카운트가 진짜 세어지는지 확인**

프리셋이 아직 이 PC 의 `~/.config/opencode` 에 없으므로, 먼저 임시로 설치한 뒤
확인하고 되돌린다.

Run:
```bash
bash scripts/install-preset.sh --force
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\dist\scripts\lib-log.ps1; . .\dist\scripts\selfcheck.ps1; (Test-PresetLoaded -Port 4399) | ConvertTo-Json"
BK=$(ls -d /c/Users/user/.config/opencode.backup-* | tail -1)
rm -rf /c/Users/user/.config/opencode && mv "$BK" /c/Users/user/.config/opencode
```
Expected: `{"Ok":true,"Agents":4,"Commands":10}`. 그리고 마지막 두 줄로
개발자의 원래 설정이 복원되어야 한다.

- [ ] **Step 6: 커밋**

```bash
git add dist/scripts/selfcheck.ps1 tests/test-selfcheck.ps1
git commit -m "feat: 자체 점검 selfcheck.ps1

프리셋 로드를 opencode serve 의 /agent·/command 개수로 확정한다
(에이전트 4 + 명령어 10). '된 것 같다' 가 아니라 숫자로 판정한다.
CAMP_SELFCHECK_FAKE 로 실제 호출 없이 단위 테스트한다."
```

---

### Task 5: 당일 런처 (`launcher.ps1` + `캠프시작.cmd`)

**Files:**
- Create: `dist/scripts/launcher.ps1`
- Create: `dist/캠프시작.cmd`
- Create: `tests/test-launcher.ps1`

**Interfaces:**
- Consumes: Task 2의 `lib-appstate.ps1`, Task 3의 `lib-team.ps1`, Task 1의 `lib-log.ps1`
- Produces:
  - `Invoke-Launcher -Number <int> -Name <string> -Parent <경로> -TemplateDir <경로> -NoLaunch`
    → `@{ Ok=$bool; Dir=<경로>; Registered=$bool }`.
    `-NoLaunch` 를 주면 앱을 실행하지 않는다(테스트용)
  - 대화형 입력은 `Read-Host` 로 조 번호와 팀 이름만 묻는다. **학생 이름은 묻지 않는다**
  - 앱 등록에 실패해도 팀 폴더 생성은 성공으로 간주하고 학생에게
    "앱에서 폴더를 골라 주세요" 안내를 띄운다 (graceful degradation)

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-launcher.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"
. "$Repo\dist\scripts\lib-team.ps1"
. "$Repo\dist\scripts\launcher.ps1"

$Template = Join-Path $Repo 'template'
$tmp = Join-Path $env:TEMP ("camplaunch-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$state = Join-Path $tmp 'appstate'
New-Item -ItemType Directory -Path $state | Out-Null
$env:CAMP_APPSTATE_DIR = $state
try {
    $r = Invoke-Launcher -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r.Ok '런처 성공'
    Assert-Contains $r.Dir '03조_지구지킴이' '팀 폴더 경로 반환'
    Assert-FileExists (Join-Path $r.Dir 'index.html') '발표자료 생성됨'
    Assert-True $r.Registered '앱에 등록됨'

    $projects = Get-RegisteredProjects
    Assert-True ($projects -contains $r.Dir) '등록부에 팀 폴더가 들어감'

    $settings = Get-Content -LiteralPath (Join-Path $state 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings.firstLaunchOnboardingComplete $true '온보딩 건너뛰기 설정됨'

    # 두 번 실행해도 안전
    $r2 = Invoke-Launcher -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r2.Ok '재실행 성공'
    Assert-Eq $r2.Dir $r.Dir '같은 폴더 재사용'
    Assert-Eq (Get-RegisteredProjects).Count 1 '등록이 중복되지 않음'

    # 잘못된 조번호
    $r3 = Invoke-Launcher -Number 99 -Name '팀' -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-Eq $r3.Ok $false '잘못된 조번호는 실패'

    # 앱 상태가 손상돼도 팀 폴더는 만들어진다 (강등)
    'broken' | Set-Content -LiteralPath (Join-Path $state 'opencode.global.dat') -Encoding utf8
    $r4 = Invoke-Launcher -Number 7 -Name '별빛' -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r4.Ok '앱 상태 손상에도 런처는 성공'
    Assert-Eq $r4.Registered $false '등록은 실패로 보고됨'
    Assert-FileExists (Join-Path $r4.Dir 'index.html') '팀 폴더는 정상 생성'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-launcher.ps1`
Expected: FAIL — `launcher.ps1` 없음

- [ ] **Step 3: 구현**

`dist/scripts/launcher.ps1`:

```powershell
# 캠프 당일 아침에 학생이 실행한다.
# 팀 배정이 당일이라 설치 시점에는 팀 폴더를 만들 수 없다. 그 간극을 메운다.

function Get-DesktopAppPath {
    $p = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop\opencode.exe'
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    # 이름이 다를 수 있으니 폴더 안의 exe 를 찾아본다
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop'
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $exe = Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File |
               Where-Object { $_.Name -notmatch 'unins' } |
               Select-Object -First 1
        if ($null -ne $exe) { return $exe.FullName }
    }
    return $null
}

function Invoke-Launcher {
    param(
        [int]$Number,
        [string]$Name,
        [string]$Parent,
        [string]$TemplateDir,
        [switch]$NoLaunch
    )

    $result = @{ Ok = $false; Dir = $null; Registered = $false }

    $dir = New-TeamFolder -Number $Number -Name $Name -Parent $Parent -TemplateDir $TemplateDir
    if ($null -eq $dir) {
        Write-Fail '조 번호는 1부터 15까지, 팀 이름에는 특수문자를 쓸 수 없어요.'
        return $result
    }
    $result.Dir = $dir
    $result.Ok = $true
    Write-Ok ('우리 팀 폴더를 만들었어요: ' + (Split-Path -Leaf $dir))

    $reg = Add-RegisteredProject -Path $dir
    $onb = Set-OnboardingComplete
    if ($reg) {
        $result.Registered = $true
        Write-Ok '앱에 우리 팀을 등록했어요.'
    }
    else {
        Write-Note '앱에 자동 등록이 안 됐어요. 앱이 열리면 "프로젝트 추가" 를 눌러'
        Write-Note ('  ' + $dir + ' 를 골라 주세요.')
    }
    if (-not $onb) {
        Write-Note '앱 첫 화면 안내를 건너뛰지 못했어요. 그냥 넘기면 됩니다.'
    }

    if (-not $NoLaunch) {
        $app = Get-DesktopAppPath
        if ($null -eq $app) {
            Write-Fail '앱을 찾을 수 없어요. 설치하기를 다시 실행해 주세요.'
        }
        else {
            Write-Step '앱을 열고 있어요...'
            Start-Process -FilePath $app | Out-Null
            Write-Ok '앱이 열렸어요! 이제 /시작 이라고 써 보세요.'
        }
    }

    return $result
}

function Start-CampLauncher([string]$TemplateDir) {
    $parent = Join-Path $env:USERPROFILE '창의디자인캠프'
    Start-CampLog (Join-Path $parent '시작기록.txt')

    Write-Step '창의디자인캠프를 시작합니다!'
    Write-Host ''
    $numText = Read-Host '우리는 몇 조예요? (1~15 숫자만)'
    $teamName = Read-Host '우리 팀 이름은 뭐예요?'

    $num = 0
    if (-not [int]::TryParse($numText, [ref]$num)) {
        Write-Fail '조 번호는 숫자로 써 주세요.'
        Stop-CampLog
        return 1
    }

    $r = Invoke-Launcher -Number $num -Name $teamName -Parent $parent -TemplateDir $TemplateDir
    Stop-CampLog
    if ($r.Ok) { return 0 } else { return 1 }
}
```

`dist/캠프시작.cmd`:

```bat
@echo off
chcp 65001 >nul
title 창의디자인캠프 시작
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\launcher.ps1; exit (Start-CampLauncher -TemplateDir '%~dp0template')"
if errorlevel 1 (
  echo.
  echo 문제가 생겼어요. 선생님을 불러 주세요.
  pause
)
```

`chcp 65001` 은 콘솔을 UTF-8 로 바꿔 한국어가 깨지지 않게 한다.

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-launcher.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add dist/scripts/launcher.ps1 dist/캠프시작.cmd tests/test-launcher.ps1
git commit -m "feat: 당일 런처 launcher.ps1 + 캠프시작.cmd

조번호·팀명만 묻고(학생 이름은 묻지 않는다) 팀 폴더를 만들어
데스크탑 앱에 등록한 뒤 앱을 실행한다.
앱 등록이 실패해도 팀 폴더 생성은 성공으로 보고하고 학생에게
폴더를 고르는 방법을 안내한다(강등)."
```

---

### Task 6: 설치 오케스트레이터 (`orchestrator.ps1`)

**Files:**
- Create: `dist/scripts/orchestrator.ps1`
- Create: `tests/test-orchestrator-dryrun.ps1`

**Interfaces:**
- Consumes: Task 1의 `lib-log.ps1`, Task 2의 `lib-appstate.ps1`, Task 3의 `lib-team.ps1`, Task 4의 `selfcheck.ps1`
- Produces:
  - `Get-InstallPlan -BundleDir <경로>` → 설치 단계 배열.
    각 원소는 `@{ Name=<한국어 이름>; File=<번들 파일명>; Args=<인자 배열>; Kind=<'msi'|'exe'|'copy'|'font'|'npm'> }`
  - `Invoke-Install -DistDir <경로> [-DryRun] [-SkipSelfCheck]` → exit code.
    `-DryRun` 은 아무 것도 설치하지 않고 실행할 명령을 로그에만 남긴다
  - `Test-Prerequisites` → `@{ Ok=$bool; Reasons=<문자열 배열> }`
    (Windows 10/11, x64, 여유 공간 5GB)
  - `Unblock-BundleFiles -DistDir <경로>` → Mark-of-the-Web 해제

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-orchestrator-dryrun.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"
. "$Repo\dist\scripts\lib-team.ps1"
. "$Repo\dist\scripts\selfcheck.ps1"
. "$Repo\dist\scripts\orchestrator.ps1"

$tmp = Join-Path $env:TEMP ("camporch-" + [guid]::NewGuid().ToString('N'))
$dist = Join-Path $tmp 'dist'
$bundle = Join-Path $dist 'bundle'
New-Item -ItemType Directory -Path $bundle -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist 'preset') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist 'secrets') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist 'template') -Force | Out-Null
$env:CAMP_APPSTATE_DIR = Join-Path $tmp 'appstate'
try {
    # 번들 파일을 가짜로 만들어 둔다
    foreach ($f in @('opencode-desktop-win-x64.exe','node-lts-x64.msi','python-3.12-amd64.exe','Git-64-bit.exe','CascadiaCode-NF.zip')) {
        'fake' | Set-Content -LiteralPath (Join-Path $bundle $f) -Encoding utf8
    }

    # --- 설치 계획 ---
    $plan = Get-InstallPlan -BundleDir $bundle
    Assert-True ($plan.Count -ge 5) '설치 계획에 5단계 이상'
    $names = @()
    foreach ($s in $plan) { $names += $s.Name }
    $joined = ($names -join '|')
    Assert-Contains $joined '노드' '계획에 Node 포함'
    Assert-Contains $joined '파이썬' '계획에 Python 포함'
    Assert-Contains $joined 'Git' '계획에 Git 포함'
    Assert-Contains $joined '글꼴' '계획에 글꼴 포함'
    Assert-Contains $joined '앱' '계획에 데스크탑 앱 포함'
    Assert-NotContains $joined 'VS Code' 'VS Code 는 계획에 없음'

    # --- per-user 설치 인자가 들어갔는지 (관리자권한 회피) ---
    $allArgs = ''
    foreach ($s in $plan) { if ($s.Args) { $allArgs += (($s.Args -join ' ') + ' ') } }
    Assert-Contains $allArgs 'ALLUSERS=0' 'Node 가 per-user 설치'
    Assert-Contains $allArgs 'InstallAllUsers=0' 'Python 이 per-user 설치'
    Assert-Contains $allArgs '/S' '데스크탑 앱이 조용한 설치'

    # --- DryRun 은 아무 것도 설치하지 않는다 ---
    $log = Join-Path $tmp 'dry.txt'
    Start-CampLog $log
    $rc = Invoke-Install -DistDir $dist -DryRun -SkipSelfCheck
    Stop-CampLog
    Assert-Eq $rc 0 'DryRun 은 성공으로 끝남'
    $content = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    Assert-Contains $content '실제로 설치하지 않습니다' 'DryRun 임을 로그에 남김'
    Assert-Contains $content '노드' 'DryRun 로그에 각 단계가 남음'

    # 프리셋이 실제로 복사되지 않았는지 (DryRun 이므로)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:CAMP_APPSTATE_DIR 'opencode.global.dat'))) 'DryRun 은 앱 상태를 건드리지 않음'

    # --- 번들 파일이 없으면 계획에서 제외되고 실패로 보고 ---
    Remove-Item -LiteralPath (Join-Path $bundle 'node-lts-x64.msi') -Force
    $plan2 = Get-InstallPlan -BundleDir $bundle
    $names2 = @()
    foreach ($s in $plan2) { $names2 += $s.Name }
    Assert-NotContains ($names2 -join '|') '노드' '없는 번들 파일은 계획에서 빠짐'

    # --- 사전 점검 ---
    $pre = Test-Prerequisites
    Assert-True ($null -ne $pre.Ok) '사전 점검이 결과를 반환'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-orchestrator-dryrun.ps1`
Expected: FAIL — `orchestrator.ps1` 없음

- [ ] **Step 3: 구현**

`dist/scripts/orchestrator.ps1`:

```powershell
# 캠프 배포판 설치 오케스트레이터.
#
# 핵심 설계: 우리가 인스톨러를 만드는 게 아니라, 이미 코드 서명된 공식
# 인스톨러들을 조용히 순차 실행한다. 그래서 서명 인증서가 필요 없다.
# 모든 구성요소는 per-user 로 설치해 관리자 권한을 요구하지 않는다.

function Test-Prerequisites {
    $reasons = @()

    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]($os.BuildNumber) -lt 19041) {
        $reasons += 'Windows 10 (2004) 이상이 필요해요.'
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        $reasons += '64비트 Windows 가 필요해요. (지금: ' + $env:PROCESSOR_ARCHITECTURE + ')'
    }
    $drive = (Get-Item $env:USERPROFILE).PSDrive.Name
    $free = (Get-PSDrive $drive).Free
    if ($free -lt 5GB) {
        $reasons += ('빈 공간이 5GB 이상 필요해요. (지금: ' + [math]::Round($free / 1GB, 1) + 'GB)')
    }

    return @{ Ok = ($reasons.Count -eq 0); Reasons = $reasons }
}

function Unblock-BundleFiles([string]$DistDir) {
    # USB·다운로드로 온 파일에는 차단 플래그가 붙는다.
    # 이걸 안 떼면 60대에서 전부 막힌다.
    Get-ChildItem -LiteralPath $DistDir -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
}

function Get-InstallPlan([string]$BundleDir) {
    $candidates = @(
        @{ Name = '노드 (AI 도구가 쓰는 부품)'; File = 'node-lts-x64.msi';            Kind = 'msi'; Args = @('/qn', 'ALLUSERS=0') },
        @{ Name = '파이썬';                     File = 'python-3.12-amd64.exe';       Kind = 'exe'; Args = @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0') },
        @{ Name = 'Git';                        File = 'Git-64-bit.exe';              Kind = 'exe'; Args = @('/VERYSILENT', '/NORESTART', '/NOCANCEL') },
        @{ Name = '글꼴';                       File = 'CascadiaCode-NF.zip';         Kind = 'font'; Args = @() },
        @{ Name = '캠프 앱';                    File = 'opencode-desktop-win-x64.exe'; Kind = 'exe'; Args = @('/S') }
    )

    $plan = @()
    foreach ($c in $candidates) {
        $path = Join-Path $BundleDir $c.File
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $c['Path'] = $path
            $plan += $c
        }
    }
    return $plan
}

function Install-Font([string]$ZipPath) {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path -LiteralPath $fontDir)) {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    }
    $tmp = Join-Path $env:TEMP ('font-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $tmp)
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Get-ChildItem -LiteralPath $tmp -Recurse -Include '*.ttf', '*.otf' -File | ForEach-Object {
            $dest = Join-Path $fontDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            Set-ItemProperty -Path $key -Name $_.BaseName -Value $dest
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Copy-PresetAndSecrets([string]$DistDir) {
    # 프리셋
    $presetSrc = Join-Path $DistDir 'preset'
    $presetDst = Join-Path $env:USERPROFILE '.config\opencode'
    if (Test-Path -LiteralPath $presetSrc -PathType Container) {
        if ((Test-Path -LiteralPath $presetDst) -and (Get-ChildItem -LiteralPath $presetDst -Force | Measure-Object).Count -gt 0) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Move-Item -LiteralPath $presetDst -Destination ($presetDst + '.backup-' + $stamp)
            Write-Note '원래 쓰던 설정은 따로 보관했어요.'
        }
        New-Item -ItemType Directory -Path $presetDst -Force | Out-Null
        Copy-Item -Path (Join-Path $presetSrc '*') -Destination $presetDst -Recurse -Force
    }

    # 키
    $sec = Join-Path $DistDir 'secrets'
    if (Test-Path -LiteralPath (Join-Path $sec 'auth.json') -PathType Leaf) {
        $dst = Join-Path $env:USERPROFILE '.local\share\opencode'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sec 'auth.json') -Destination $dst -Force
    }
    foreach ($f in @('credentials.json', 'config.json')) {
        $src = Join-Path $sec $f
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            $dst = Join-Path $env:USERPROFILE '.config\higgsfield'
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

function Invoke-Install {
    param(
        [Parameter(Mandatory=$true)][string]$DistDir,
        [switch]$DryRun,
        [switch]$SkipSelfCheck
    )

    if ($DryRun) { Write-Note '연습 모드입니다. 실제로 설치하지 않습니다.' }

    Write-Step '컴퓨터를 확인하고 있어요'
    $pre = Test-Prerequisites
    if (-not $pre.Ok) {
        foreach ($r in $pre.Reasons) { Write-Fail $r }
        return 1
    }
    Write-Ok '컴퓨터는 괜찮아요'

    Write-Step '파일 차단을 풀고 있어요'
    if (-not $DryRun) { Unblock-BundleFiles -DistDir $DistDir }
    Write-Ok '차단을 풀었어요'

    $plan = Get-InstallPlan -BundleDir (Join-Path $DistDir 'bundle')
    $i = 0
    foreach ($step in $plan) {
        $i++
        Write-Step ("$i/$($plan.Count) " + $step.Name + ' 을(를) 설치하고 있어요')
        if ($DryRun) {
            Write-Note ('  (연습) ' + $step.File + ' ' + ($step.Args -join ' '))
            continue
        }

        if ($step.Kind -eq 'font') {
            Install-Font -ZipPath $step.Path
        }
        elseif ($step.Kind -eq 'msi') {
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/i', $step.Path) + $step.Args) -PassThru -Wait
            if ($p.ExitCode -ne 0) { Write-Fail ($step.Name + ' 설치에 실패했어요.'); return 1 }
        }
        else {
            $p = Start-Process -FilePath $step.Path -ArgumentList $step.Args -PassThru -Wait
            if ($p.ExitCode -ne 0) { Write-Fail ($step.Name + ' 설치에 실패했어요.'); return 1 }
        }
        Write-Ok ($step.Name + ' 을(를) 설치했어요')
    }

    Write-Step '캠프 설정을 넣고 있어요'
    if (-not $DryRun) { Copy-PresetAndSecrets -DistDir $DistDir }
    Write-Ok '캠프 설정을 넣었어요'

    Write-Step '연습 폴더를 만들고 있어요'
    if (-not $DryRun) {
        $parent = Join-Path $env:USERPROFILE '창의디자인캠프'
        $practice = Join-Path $parent '연습'
        if (-not (Test-Path -LiteralPath $practice)) {
            New-Item -ItemType Directory -Path $practice -Force | Out-Null
            $tpl = Join-Path $DistDir 'template'
            if (Test-Path -LiteralPath $tpl -PathType Container) {
                Copy-Item -Path (Join-Path $tpl '*') -Destination $practice -Recurse -Force
            }
        }
        Add-RegisteredProject -Path $practice | Out-Null
        Set-OnboardingComplete | Out-Null
    }
    Write-Ok '연습 폴더를 만들었어요'

    if ($SkipSelfCheck) { return 0 }

    Write-Host ''
    return (Invoke-SelfCheck)
}
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-orchestrator-dryrun.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: 커밋**

```bash
git add dist/scripts/orchestrator.ps1 tests/test-orchestrator-dryrun.ps1
git commit -m "feat: 설치 오케스트레이터 orchestrator.ps1

서명된 공식 인스톨러들을 per-user·조용히 순차 실행한다.
Mark-of-the-Web 해제를 먼저 하고(안 하면 60대에서 다 막힌다),
프리셋·키를 배치한 뒤 연습 폴더를 앱에 등록하고 자체 점검으로 끝낸다.
-DryRun 으로 실제 설치 없이 계획과 순서를 검증한다."
```

---

### Task 7: 진입점 `.cmd` 2개

**Files:**
- Create: `dist/설치하기.cmd`
- Create: `dist/점검하기.cmd`

**Interfaces:**
- Consumes: Task 6의 `Invoke-Install`, Task 4의 `Invoke-SelfCheck`
- Produces: 학생이 더블클릭하는 진입점. 종료 코드 0이면 성공

- [ ] **Step 1: 구현**

`dist/설치하기.cmd`:

```bat
@echo off
chcp 65001 >nul
title 창의디자인캠프 설치
cd /d "%~dp0"
echo.
echo   창의디자인캠프 준비를 시작합니다.
echo   10분쯤 걸려요. 창을 닫지 말고 기다려 주세요.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\selfcheck.ps1; . .\scripts\orchestrator.ps1; Start-CampLog (Join-Path $env:USERPROFILE '창의디자인캠프\설치기록.txt'); $rc = Invoke-Install -DistDir '%~dp0'; Stop-CampLog; exit $rc"
echo.
if errorlevel 1 (
  echo   준비가 다 안 됐어요. 선생님을 불러 주세요.
  echo   기록 파일: %USERPROFILE%\창의디자인캠프\설치기록.txt
) else (
  echo   준비 끝! 캠프 당일에 "캠프시작" 을 눌러 주세요.
)
echo.
pause
```

`dist/점검하기.cmd`:

```bat
@echo off
chcp 65001 >nul
title 창의디자인캠프 점검
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\lib-log.ps1; . .\scripts\selfcheck.ps1; Start-CampLog (Join-Path $env:USERPROFILE '창의디자인캠프\점검기록.txt'); $rc = Invoke-SelfCheck; Stop-CampLog; exit $rc"
echo.
pause
```

- [ ] **Step 2: DryRun 으로 진입점이 실제로 도는지 확인**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "cd dist; . .\scripts\lib-log.ps1; . .\scripts\lib-appstate.ps1; . .\scripts\lib-team.ps1; . .\scripts\selfcheck.ps1; . .\scripts\orchestrator.ps1; Invoke-Install -DistDir (Get-Location).Path -DryRun -SkipSelfCheck"
```
Expected: 연습 모드 안내와 각 단계가 한국어로 출력되고 exit 0.
`bundle/` 이 비어 있으면 설치 단계가 0개로 나오는데, 그것도 정상이다
(Task 8 에서 채운다)

- [ ] **Step 3: 한국어가 콘솔에서 깨지지 않는지 눈으로 확인**

Run: `cmd //c "dist\점검하기.cmd"`
Expected: 한국어가 정상 출력된다. 깨지면 `chcp 65001` 이 빠졌거나
`.cmd` 파일이 UTF-8 로 저장되지 않은 것이다

- [ ] **Step 4: 커밋**

```bash
git add "dist/설치하기.cmd" "dist/점검하기.cmd"
git commit -m "feat: 진입점 설치하기.cmd / 점검하기.cmd

chcp 65001 로 콘솔을 UTF-8 로 바꿔 한국어가 깨지지 않게 한다.
실패 시 학생에게 기록 파일 위치를 한국어로 알려준다."
```

---

### Task 8: 번들 수집 + 배포판 빌드

**Files:**
- Create: `scripts/fetch-bundle.ps1`
- Create: `scripts/build-dist.ps1`
- Create: `tests/test-build-dist.ps1`

**Interfaces:**
- Consumes: 없음 (외부 다운로드)
- Produces:
  - `fetch-bundle.ps1` — `dist/bundle/` 에 구성요소를 내려받고 **각 파일의
    코드 서명을 검증**한다. 서명이 유효하지 않으면 그 파일을 지우고 실패로 보고
  - `build-dist.ps1` — `camp-preset/` → `dist/preset/`, `template/` → `dist/template/`
    복사. `dist/secrets/` 는 손대지 않는다(사람이 직접 넣는다).
    `-Verify` 를 주면 배포판에 있어야 할 파일이 다 있는지 검사

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-build-dist.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\scripts\build-dist.ps1"

# 빌드 실행 (실제 리포에 대고 돌린다 — preset/template 복사만 한다)
$rc = Invoke-BuildDist -RepoDir $Repo
Assert-Eq $rc 0 '빌드 성공'

Assert-FileExists (Join-Path $Repo 'dist\preset\AGENTS.md') '프리셋 AGENTS.md 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\opencode.json') '프리셋 설정 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\agent\도우미.md') '에이전트 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\command\도와줘.md') '명령어 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\skills\web-slides\SKILL.md') '스킬 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\template\index.html') '템플릿 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\template\우리팀.md') '팀 기록 파일 복사됨'

# opencode 가 만든 부산물은 배포판에 들어가면 안 된다
Assert-True (-not (Test-Path (Join-Path $Repo 'dist\preset\node_modules'))) 'node_modules 는 배포되지 않음'
Assert-True (-not (Test-Path (Join-Path $Repo 'dist\preset\package.json'))) 'package.json 은 배포되지 않음'

# 검증 모드: secrets 가 비어 있으면 경고하되 실패는 아니다
$v = Test-DistComplete -DistDir (Join-Path $Repo 'dist')
Assert-True ($null -ne $v.Missing) '검증이 결과를 반환'

if (Test-Summary) { exit 0 } else { exit 1 }
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-build-dist.ps1`
Expected: FAIL — `build-dist.ps1` 없음

- [ ] **Step 3: 구현**

`scripts/build-dist.ps1`:

```powershell
# 리포의 camp-preset/ 와 template/ 를 dist/ 로 복사해 배포판을 완성한다.
# opencode 가 camp-preset 안에 만들어 둔 node_modules·package.json 은 제외한다.

function Invoke-BuildDist([string]$RepoDir) {
    $exclude = @('node_modules', 'package.json', 'package-lock.json', 'bun.lock', '.gitignore')

    $pairs = @(
        @{ Src = (Join-Path $RepoDir 'camp-preset'); Dst = (Join-Path $RepoDir 'dist\preset') },
        @{ Src = (Join-Path $RepoDir 'template');    Dst = (Join-Path $RepoDir 'dist\template') }
    )

    foreach ($p in $pairs) {
        if (-not (Test-Path -LiteralPath $p.Src -PathType Container)) {
            Write-Host ('원본이 없습니다: ' + $p.Src)
            return 1
        }
        if (Test-Path -LiteralPath $p.Dst) { Remove-Item -Recurse -Force $p.Dst }
        New-Item -ItemType Directory -Path $p.Dst -Force | Out-Null

        Get-ChildItem -LiteralPath $p.Src -Force | Where-Object {
            $exclude -notcontains $_.Name
        } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $p.Dst -Recurse -Force
        }
    }
    return 0
}

function Test-DistComplete([string]$DistDir) {
    $required = @(
        'preset\AGENTS.md',
        'preset\opencode.json',
        'template\index.html',
        '설치하기.cmd',
        '점검하기.cmd',
        '캠프시작.cmd',
        'scripts\orchestrator.ps1',
        'scripts\selfcheck.ps1',
        'scripts\launcher.ps1'
    )
    $bundleFiles = @(
        'bundle\opencode-desktop-win-x64.exe',
        'bundle\node-lts-x64.msi',
        'bundle\python-3.12-amd64.exe',
        'bundle\Git-64-bit.exe',
        'bundle\CascadiaCode-NF.zip'
    )
    $secretFiles = @(
        'secrets\auth.json',
        'secrets\credentials.json',
        'secrets\config.json'
    )

    $missing = @()
    foreach ($r in ($required + $bundleFiles + $secretFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $DistDir $r))) { $missing += $r }
    }
    return @{ Ok = ($missing.Count -eq 0); Missing = $missing }
}
```

`scripts/fetch-bundle.ps1`:

```powershell
# 배포판 구성요소를 내려받고 코드 서명을 검증한다.
# 서명이 유효하지 않은 파일은 학생 노트북에 넣지 않는다.

function Get-BundleSources {
    return @(
        @{ Name = 'opencode-desktop-win-x64.exe'
           Url  = 'https://github.com/anomalyco/opencode/releases/download/v1.18.20/opencode-desktop-win-x64.exe' },
        @{ Name = 'node-lts-x64.msi'
           Url  = 'https://nodejs.org/dist/v22.20.0/node-v22.20.0-x64.msi' },
        @{ Name = 'python-3.12-amd64.exe'
           Url  = 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe' },
        @{ Name = 'Git-64-bit.exe'
           Url  = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe' },
        @{ Name = 'CascadiaCode-NF.zip'
           Url  = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/CascadiaCode.zip' }
    )
}

function Invoke-FetchBundle([string]$BundleDir) {
    if (-not (Test-Path -LiteralPath $BundleDir)) {
        New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
    }
    $failed = @()
    foreach ($s in (Get-BundleSources)) {
        $dest = Join-Path $BundleDir $s.Name
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            Write-Host ('이미 있음: ' + $s.Name)
        }
        else {
            Write-Host ('받는 중: ' + $s.Name)
            try {
                Invoke-WebRequest -Uri $s.Url -OutFile $dest -UseBasicParsing
            }
            catch {
                Write-Host ('  실패: ' + $s.Name)
                $failed += $s.Name
                continue
            }
        }

        # zip 은 서명 대상이 아니다
        if ($s.Name -like '*.zip') { continue }

        $sig = Get-AuthenticodeSignature -LiteralPath $dest
        if ($sig.Status -ne 'Valid') {
            Write-Host ('  서명 검증 실패(' + $sig.Status + '): ' + $s.Name)
            Remove-Item -LiteralPath $dest -Force
            $failed += $s.Name
        }
        else {
            Write-Host ('  서명 확인: ' + $sig.SignerCertificate.Subject)
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host ('받지 못한 파일: ' + ($failed -join ', '))
        return 1
    }
    return 0
}
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-build-dist.ps1`
Expected: PASS — `0 failed`

- [ ] **Step 5: 실제로 번들을 내려받고 서명을 검증**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\fetch-bundle.ps1; exit (Invoke-FetchBundle -BundleDir '.\dist\bundle')"
```
Expected: 5개 파일을 받고 exe/msi 4개 모두 `서명 확인` 이 출력된다.
하나라도 서명 검증에 실패하면 그 URL 이 잘못되었거나 배포처가 바뀐 것이므로
URL 을 고친다. **번들 파일은 `.gitignore` 로 커밋되지 않는다**

- [ ] **Step 6: 커밋**

```bash
git add scripts/fetch-bundle.ps1 scripts/build-dist.ps1 tests/test-build-dist.ps1
git commit -m "feat: 번들 수집 + 배포판 빌드 스크립트

fetch-bundle 은 구성요소를 받고 코드 서명을 검증한다 — 서명이 유효하지
않은 파일은 학생 노트북에 넣지 않는다.
build-dist 는 camp-preset/template 을 dist 로 복사하며 opencode 가 만든
node_modules·package.json 부산물을 제외한다."
```

---

### Task 9: 팀 협업용 `slides/` 분리 구조

주최측 방침은 자체 Git 으로 팀장이 합치는 것이다. 4명이 같은 `index.html` 을
고치면 병합 충돌이 나고 초5 가 해결할 수 없으므로, 기여를 파일 단위로 나눈다.

**Files:**
- Modify: `template/index.html` (slides 조립 지점 주석 추가)
- Create: `template/slides/.gitkeep`
- Modify: `template/우리팀.md` (내 번호 기록)
- Modify: `camp-preset/skills/web-slides/SKILL.md` (분리 규칙)
- Create: `camp-preset/command/합쳐줘.md`
- Modify: `camp-preset/agent/디자이너.md` (조립 역할)
- Modify: `tests/test-template.sh`, `tests/test-commands.sh`, `tests/test-skills.sh`
- Modify: `docs/운영/학생용-치트시트.md`

**Interfaces:**
- Consumes: 기존 프리셋·템플릿
- Produces:
  - 팀 폴더 구조에 `slides/1번친구.html` ~ `slides/4번친구.html`
  - `/합쳐줘` 명령 (agent: 디자이너) — `slides/*.html` 을 읽어 `index.html` 로 조립
  - `우리팀.md` 에 `- 나는 몇 번 친구: (아직 안 정함)` 항목 추가

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test-commands.sh` 의 `CMDS` 에 `합쳐줘` 를 추가하고, `summary` 직전에 추가:

```bash
# /합쳐줘 는 slides 조립을 지시해야 한다
M="$(cat "$REPO/camp-preset/command/합쳐줘.md" 2>/dev/null || echo '')"
assert_contains "$M" "slides/" "/합쳐줘 가 slides 폴더를 참조"
assert_contains "$M" "index.html" "/합쳐줘 가 조립 대상을 명시"
```

`tests/test-template.sh` 의 `summary` 직전에 추가:

```bash
# 팀 협업: slides 분리 구조
if [ -d "$REPO/template/slides" ]; then pass "slides 폴더 존재"
else fail "slides 폴더 없음"; fi
assert_contains "$H" "여기에 친구들 슬라이드가 들어갑니다" "index.html 에 조립 지점 표시"
TEAMDOC="$(cat "$REPO/template/우리팀.md" 2>/dev/null || echo '')"
assert_contains "$TEAMDOC" "나는 몇 번 친구" "우리팀.md 에 내 번호 항목"
```

`tests/test-skills.sh` 의 `summary` 직전에 추가:

```bash
assert_contains "$W" "slides/" "web-slides 가 분리 구조를 설명"
assert_contains "$W" "자기 파일만" "web-slides 가 자기 파일만 고치라고 지시"
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/run-all.sh`
Expected: FAIL — `/합쳐줘` 없음, `slides` 폴더 없음, 스킬 문구 없음

- [ ] **Step 3: 구현**

`template/slides/.gitkeep` — 빈 파일

`template/index.html` 의 5번 슬라이드("우리가 만든 것")를 이렇게 바꾼다:

```html
<!-- 5. 우리가 만든 것 -->
<section class="slide">
  <h2>우리가 만든 것</h2>
  <p>여기에 우리가 만든 그림이 들어갑니다.</p>
</section>

<!-- 여기에 친구들 슬라이드가 들어갑니다 (합쳐줘 를 쓰면 아래에 채워져요) -->
```

`template/우리팀.md` 의 팀 이름 줄 다음에 추가:

```markdown
- 나는 몇 번 친구: (아직 안 정함)
```

`camp-preset/command/합쳐줘.md`:

```markdown
---
description: 친구들이 각자 만든 슬라이드를 하나로 합칩니다 (팀장이 씁니다)
agent: 디자이너
---
`web-slides` 스킬을 읽어라.

팀 폴더의 `slides/` 안에 있는 `*.html` 파일을 모두 읽어라.
파일 이름 순서(1번친구 → 4번친구)대로 각 파일의 `<section class="slide">` 를
`index.html` 의 "여기에 친구들 슬라이드가 들어갑니다" 주석 바로 아래에 넣어라.

주의:
- 이미 합쳐진 것이 있으면 지우고 다시 합쳐라. 중복으로 쌓지 마라.
- 친구들 파일 안의 그림 경로가 `assets/` 로 시작하는지 확인하라.
- `slides/` 가 비어 있으면 학생에게 이렇게 말하라:
  "아직 친구들 슬라이드가 안 들어왔어요. 친구들에게 보내 달라고 해 볼까요?"

다 하면 몇 장이 합쳐졌는지 알리고 `/보여줘` 를 권하라.
```

`camp-preset/skills/web-slides/SKILL.md` 의 "## 절대 규칙" 바로 뒤에 절 추가:

```markdown
## 팀으로 만들 때는 자기 파일만 고친다

한 팀은 4명이고 각자 노트북이 따로다. 같은 `index.html` 을 여러 명이 고치면
합칠 때 충돌이 나서 되돌릴 수 없다.

- 학생은 `우리팀.md` 의 "나는 몇 번 친구" 를 보고 **`slides/N번친구.html` 만**
  만들고 고친다
- 그 파일에는 `<section class="slide">` 만 넣는다. `<html>`·`<head>`·`<style>` 은
  넣지 않는다 (`index.html` 의 것을 그대로 물려받는다)
- `index.html` 을 직접 고치는 것은 **팀장이 `/합쳐줘` 를 쓸 때만** 이다
- 그림·음악·영상은 `assets/` 에 그대로 두고 상대경로로 참조한다.
  파일명은 래퍼가 번호를 붙이므로 겹치지 않는다
```

`camp-preset/agent/디자이너.md` 의 "## 장을 추가할 때" 앞에 절 추가:

```markdown
## 혼자 만들 때와 팀으로 합칠 때

`우리팀.md` 의 "나는 몇 번 친구" 를 먼저 확인한다.

- 번호가 정해져 있으면 그 학생의 `slides/N번친구.html` 만 고친다
- 팀장이 "합쳐줘" 라고 하면 `slides/*.html` 을 모아 `index.html` 로 조립한다
- 번호가 아직 없으면 한 번만 묻는다: "몇 번 친구예요?"
```

`docs/운영/학생용-치트시트.md` 의 명령어 표에 한 줄 추가 (`/제출` 위):

```markdown
| `/합쳐줘` | 친구들이 만든 슬라이드를 하나로 합쳐요 (팀장만) |
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/run-all.sh`
Expected: PASS — 전체 통과

- [ ] **Step 5: PowerShell 팀 폴더 테스트도 여전히 통과하는지 확인**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-team.ps1`
Expected: PASS. `slides/` 가 템플릿에 추가됐으니 복사도 되어야 한다.
안 되면 `New-TeamFolder` 의 `Copy-Item -Recurse` 가 빈 폴더를 건너뛴 것이므로
`.gitkeep` 이 들어 있는지 확인한다

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "feat: 팀 협업용 slides/ 분리 구조 + /합쳐줘

4명이 같은 index.html 을 고치면 병합 충돌이 나고 초5 는 해결할 수 없다.
각자 slides/N번친구.html 만 고치게 해 충돌을 구조적으로 제거하고,
팀장이 /합쳐줘 로 조립한다. 자체 Git 이 늦어져도 USB 로 slides 폴더만
주고받으면 동일하게 동작한다."
```

---

### Task 10: 실기기 E2E (실제 설치)

이 PC 에서 배포판을 실제로 실행해 초록불 4개까지 도달하는지 확인한다.
이 태스크만 실제 설치와 실제 API 호출(크레딧 1)을 한다.

**Files:**
- Create: `tests/E2E-체크리스트.md`

**Interfaces:**
- Consumes: Task 1~9 전체
- Produces: 없음 (검증 기록)

- [ ] **Step 1: 배포판 완성**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\build-dist.ps1; Invoke-BuildDist -RepoDir (Get-Location).Path"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\fetch-bundle.ps1; Invoke-FetchBundle -BundleDir '.\dist\bundle'"
```
그리고 `dist/secrets/` 에 키 3개를 사람이 직접 복사한다:
```bash
cp ~/.local/share/opencode/auth.json dist/secrets/
cp ~/.config/higgsfield/credentials.json dist/secrets/
cp ~/.config/higgsfield/config.json dist/secrets/
```
**주의: `dist/secrets/` 는 `.gitignore` 에 있어 커밋되지 않는다. 확인하라.**

Run: `git status --porcelain dist/secrets` → 출력이 없어야 한다

- [ ] **Step 2: 배포판 완성도 검증**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\build-dist.ps1; (Test-DistComplete -DistDir '.\dist') | ConvertTo-Json"
```
Expected: `{"Ok":true,"Missing":[]}`

- [ ] **Step 3: 개발자 환경 백업 (되돌릴 수 있게)**

Run:
```bash
cp -r ~/.config/opencode ~/.config/opencode.e2e-backup 2>/dev/null || true
cp -r "$APPDATA/ai.opencode.desktop" "$APPDATA/ai.opencode.desktop.e2e-backup" 2>/dev/null || true
```

- [ ] **Step 4: 실제 설치 실행**

Run: `cmd //c "dist\설치하기.cmd"`

확인할 것:
- 관리자 권한을 **한 번도** 묻지 않는다
- 각 단계가 한국어로 표시되고 깨지지 않는다
- 마지막에 초록불 4개 (`도구`/`설정`/`AI`/`그림`)
- 소요 시간 10분 이내
- `~/창의디자인캠프/설치기록.txt` 가 만들어졌고 한국어가 정상

- [ ] **Step 5: 런처 실행**

Run: `cmd //c "dist\캠프시작.cmd"` → 조 번호 `9`, 팀 이름 `바다친구` 입력

확인할 것:
- `~/창의디자인캠프/09조_바다친구/` 가 생겼고 `index.html`·`slides/`·`assets/` 가 있다
- 표지에 `09조 바다친구` 가 들어갔다
- **데스크탑 앱이 열리고, 프로젝트 목록에 `09조_바다친구` 가 이미 있다**
- 온보딩 화면이 뜨지 않는다
- 입력부터 앱이 열릴 때까지 2분 이내

- [ ] **Step 6: 앱 안에서 학생 흐름 확인**

데스크탑 앱에서 `09조_바다친구` 프로젝트를 열고 세션을 만들어:
1. `/도와줘` → 다음 할 일 하나를 한국어로 제안하는가
2. `/포스터` → 그림이 만들어지고 `assets/` 에 저장되는가 (크레딧 1)
3. `/보여줘` → 브라우저에서 발표자료가 열리는가

- [ ] **Step 7: 결과를 체크리스트로 기록**

`tests/E2E-체크리스트.md` 에 각 항목의 실제 결과와 소요 시간, 발견한 문제를
적는다. 통과/실패를 사실대로 쓴다.

- [ ] **Step 8: 개발자 환경 복원**

Run:
```bash
rm -rf ~/.config/opencode && mv ~/.config/opencode.e2e-backup ~/.config/opencode
rm -rf "$APPDATA/ai.opencode.desktop" && mv "$APPDATA/ai.opencode.desktop.e2e-backup" "$APPDATA/ai.opencode.desktop"
```
Expected: 개발자의 원래 opencode 설정과 앱 상태가 돌아온다

- [ ] **Step 9: 커밋**

```bash
git add tests/E2E-체크리스트.md
git commit -m "test: 실기기 E2E 체크리스트와 실행 결과

실제 설치 → 초록불 4개 → 런처 → 앱에서 학생 흐름까지 확인한 기록."
```

---

### Task 11: 운영 문서 갱신

**Files:**
- Modify: `docs/운영/사전온라인교육-2시간.md`
- Modify: `docs/운영/멘토용-트러블슈팅.md`
- Modify: `README.md`
- Modify: `tests/test-docs.sh`

**Interfaces:**
- Consumes: Task 1~10
- Produces: 없음

- [ ] **Step 1: 테스트에 배포판 문서 검증 추가**

`tests/test-docs.sh` 의 `summary` 직전에 추가:

```bash
# 사전교육 문서가 실제 진입점 이름을 쓰는가
G="$(cat "$REPO/docs/운영/사전온라인교육-2시간.md" 2>/dev/null || echo '')"
assert_contains "$G" "설치하기" "사전교육 문서가 설치하기 진입점을 안내"
assert_contains "$G" "초록불" "사전교육 문서가 자체 점검을 안내"

# 멘토 문서가 점검하기·캠프시작을 안내하는가
T="$(cat "$REPO/docs/운영/멘토용-트러블슈팅.md" 2>/dev/null || echo '')"
assert_contains "$T" "점검하기" "멘토 문서가 재점검 방법을 안내"
assert_contains "$T" "캠프시작" "멘토 문서가 런처를 안내"

# README 가 배포판 빌드 절차를 담는가
R="$(cat "$REPO/README.md" 2>/dev/null || echo '')"
assert_contains "$R" "build-dist" "README 에 배포판 빌드 절차"
assert_contains "$R" "fetch-bundle" "README 에 번들 수집 절차"
```

- [ ] **Step 2: 테스트를 실행해 실패를 확인**

Run: `bash tests/test-docs.sh`
Expected: FAIL — 추가한 6개 항목이 실패

- [ ] **Step 3: 문서 갱신**

`docs/운영/사전온라인교육-2시간.md` 의 "0:00 ~ 0:30 설치" 절을 이렇게 바꾼다:

```markdown
## 0:00 ~ 0:30 설치

1. 배포판 폴더(USB 또는 내려받은 ZIP)에서 **`설치하기`** 를 더블클릭한다
2. 10분쯤 걸린다. 창을 닫지 않게 지도한다.
   **관리자 권한을 묻지 않는다** — 물어보면 그 노트북은 정책이 다른 것이므로
   따로 표시해 둔다
3. 마지막에 **초록불 4개**(도구 / 설정 / AI / 그림)를 확인한다
4. 하나라도 빨간불이면 화면을 캡처해 채팅으로 보내게 한다

**안 될 때**: 백신이 막는 경우가 가장 많다. 설치 폴더를 예외로 추가한다.
그래도 안 되면 캠프 당일 USB 재설치 대상 명단에 올린다.
기록 파일 위치: `내 문서 상위 폴더\창의디자인캠프\설치기록.txt`
```

같은 문서의 "0:30 ~ 1:00" 첫 항목을 이렇게 바꾼다:

```markdown
1. **`캠프시작`** 을 더블클릭 → 조 번호와 팀 이름을 넣어 연습 팀을 만든다
   (실제 조 배정은 캠프 당일이므로 여기서는 연습용 이름을 쓴다)
```

`docs/운영/멘토용-트러블슈팅.md` 의 표 맨 위에 세 줄 추가:

```markdown
| 앱에 우리 팀이 안 보임 | 자동 등록 실패 | 앱에서 "프로젝트 추가" → `창의디자인캠프\NN조_팀명` 선택 |
| 설치가 중간에 멈춤 | 구성요소 설치 실패 | `설치하기` 를 다시 실행한다(멱등). 그래도 멈추면 기록 파일의 마지막 [진행] 줄을 확인 |
| 초록불이 2개만 켜짐 | 네트워크 미연결 | 인터넷 연결 후 `점검하기` 재실행 |
```

`README.md` 에 절 추가 (`## 테스트` 앞):

```markdown
## 배포판 만들기 (주최측용)

```powershell
# 1) 프리셋·템플릿을 dist/ 로 복사
powershell -File scripts\build-dist.ps1

# 2) 구성요소 내려받기 + 코드 서명 검증
powershell -File scripts\fetch-bundle.ps1

# 3) 키 3개를 dist\secrets\ 에 직접 복사
#    auth.json (DeepSeek) / credentials.json, config.json (Higgsfield)

# 4) 완성도 검증
powershell -Command ". .\scripts\build-dist.ps1; Test-DistComplete -DistDir '.\dist'"
```

`dist/bundle/` 과 `dist/secrets/` 는 `.gitignore` 에 있다.
**키를 커밋하지 않도록 `git status` 로 확인한다.**

학생에게는 `dist/` 폴더 전체를 USB 또는 ZIP 으로 전달한다.
학생은 `설치하기` → (캠프 당일) `캠프시작` 만 누르면 된다.
```

`README.md` 의 구성 표에 두 줄 추가:

```markdown
| `dist/` | 학생에게 전달되는 배포판 (진입점 3개 + 스크립트) |
| `docs/superpowers/specs/` | 설계 문서 (프리셋 / 배포판) |
```

- [ ] **Step 4: 테스트를 실행해 통과를 확인**

Run: `bash tests/test-docs.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: 전체 테스트 (bash + PowerShell 양쪽)**

Run:
```bash
bash tests/run-all.sh
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1
```
Expected: 둘 다 통과

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "docs: 배포판 기준으로 운영 문서 갱신

사전교육 절차를 설치하기/캠프시작 진입점과 초록불 4개 기준으로 다시 쓰고,
멘토 트러블슈팅에 자동 등록 실패·설치 중단·부분 초록불 대응을 추가한다.
README 에 주최측용 배포판 빌드 절차를 넣는다."
```

---

## Self-Review 결과

**사양 커버리지** — 설계 문서의 각 절이 태스크로 덮였는지 확인했다.

| 사양 절 | 구현 태스크 |
|---|---|
| 4. 구성 (폴더 구조) | Task 1(골격), 7(진입점), 8(빌드) |
| 5. 설치 순서 10단계 | Task 6 |
| 6. 자체 점검 4종 | Task 4 |
| 7. 당일 런처 | Task 5 |
| 8. 팀 협업 slides 분리 | Task 9 |
| 9. 실패 대응 | Task 6(멱등·사전점검), 11(멘토 문서) |
| 11. 성공 판정 | Task 10 (실기기 E2E) |

**미구현으로 남기는 것** (사양에서 의도적으로 제외):
- macOS 배포판 — Windows 우선 결정
- 자체 Git 호스팅 연동 — Task 9의 파일 분리로 종속성을 끊었고, 연동 자체는
  별도 프로젝트
- USB 물리 제작·배송 — 운영 업무

**타입 일관성** — `Invoke-Launcher`/`Invoke-Install`/`Test-PresetLoaded` 의
반환 해시테이블 키(`Ok`/`Dir`/`Registered`/`Agents`/`Commands`/`Credits`)를
정의한 태스크와 사용하는 태스크에서 같은 이름으로 맞췄다.
`Get-TeamFolderName`/`New-TeamFolder` 의 조번호 규칙은 `new-team.sh` 와
Task 3 Step 5 에서 교차 검증한다.

## 남은 열린 질문 (사양 12절)

1. **자체 Git 호스팅 완성 시점** — Task 9로 종속성은 끊었으나 팀장 병합 흐름의
   실사용 가능성은 그 일정에 달려 있다
2. **학생 노트북 사양 분포** — 사전교육 때 조사 (RAM/OS/아키텍처).
   arm64 노트북이 있으면 `opencode-desktop-win-arm64.exe` 를 번들에 추가해야 한다
3. **USB 개수** — 사전교육 미설치자 규모에 따라 결정
4. **발표 환경** — 프로젝터 연결 방식. `/제출` 과 발표 흐름에 영향
