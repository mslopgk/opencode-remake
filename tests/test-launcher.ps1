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

    $projects = @(Get-RegisteredProjects)
    Assert-True ($projects -contains $r.Dir) '등록부에 팀 폴더가 들어감'

    $settings = Get-Content -LiteralPath (Join-Path $state 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings.firstLaunchOnboardingComplete $true '온보딩 건너뛰기 설정됨'

    # 두 번 실행해도 안전
    $r2 = Invoke-Launcher -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template -NoLaunch
    Assert-True $r2.Ok '재실행 성공'
    Assert-Eq $r2.Dir $r.Dir '같은 폴더 재사용'
    Assert-Eq (@(Get-RegisteredProjects)).Count 1 '등록이 중복되지 않음'

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
