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
    # 런처는 아무것도 묻지 않는다. 조 번호·팀 이름은 도우미가 대화로 받는다.
    $r = Invoke-Launcher -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r.Ok '런처 성공'
    Assert-Contains $r.Dir '내캠페인' '작업 폴더 경로 반환'
    Assert-FileExists (Join-Path $r.Dir 'index.html') '발표자료 생성됨'
    Assert-FileExists (Join-Path $r.Dir '우리팀.md') '팀 기록장 생성됨'
    Assert-True $r.Registered '앱에 등록됨'

    $projects = @(Get-RegisteredProjects)
    Assert-True ($projects -contains $r.Dir) '등록부에 작업 폴더가 들어감'

    $settings = Get-Content -LiteralPath (Join-Path $state 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings.firstLaunchOnboardingComplete $true '온보딩 건너뛰기 설정됨'

    # 팀 정보는 비워 둔 채로 시작한다 (도우미가 채운다)
    $doc = Get-Content -LiteralPath (Join-Path $r.Dir '우리팀.md') -Raw -Encoding UTF8
    Assert-Contains $doc '조 번호: (아직 안 정함)' '조 번호는 도우미가 채운다'
    Assert-Contains $doc '팀 이름: (아직 안 정함)' '팀 이름은 도우미가 채운다'

    # 두 번 실행해도 안전 (학생 작업물을 덮어쓰지 않는다)
    'STUDENT WORK' | Set-Content -LiteralPath (Join-Path $r.Dir '메모.txt') -Encoding utf8
    $r2 = Invoke-Launcher -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r2.Ok '재실행 성공'
    Assert-Eq $r2.Dir $r.Dir '같은 폴더 재사용'
    Assert-FileExists (Join-Path $r.Dir '메모.txt') '학생 작업물이 보존됨'
    Assert-Eq (@(Get-RegisteredProjects)).Count 1 '등록이 중복되지 않음'

    # 템플릿이 없으면 실패로 보고한다
    $r3 = Invoke-Launcher -Parent $tmp -TemplateDir (Join-Path $tmp '없는템플릿') -NoLaunch
    Assert-Eq $r3.Ok $false '템플릿이 없으면 실패'

    # 앱 상태가 손상돼도 작업 폴더는 만들어진다 (강등)
    $tmp2 = Join-Path $tmp 'second'
    'broken' | Set-Content -LiteralPath (Join-Path $state 'opencode.global.dat') -Encoding utf8
    $r4 = Invoke-Launcher -Parent $tmp2 -TemplateDir $Template -NoLaunch
    Assert-True $r4.Ok '앱 상태 손상에도 런처는 성공'
    Assert-Eq $r4.Registered $false '등록은 실패로 보고됨'
    Assert-FileExists (Join-Path $r4.Dir 'index.html') '작업 폴더는 정상 생성'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
