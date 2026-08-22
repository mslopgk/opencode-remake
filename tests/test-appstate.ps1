$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"

$tmp = Join-Path $env:TEMP ("campstate-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$env:CAMP_APPSTATE_DIR = $tmp
try {
    # --- 1) 상태 파일이 아예 없는 새 노트북 ---
    Assert-Eq (@(Get-RegisteredProjects)).Count 0 '상태 파일이 없으면 빈 목록'

    $ok = Add-RegisteredProject -Path 'C:\창의디자인캠프\연습'
    Assert-True $ok '상태 파일이 없어도 등록 성공'
    $projects = @(Get-RegisteredProjects)
    Assert-Eq $projects.Count 1 '등록 후 1개'
    Assert-Eq $projects[0] 'C:\창의디자인캠프\연습' '등록된 경로가 일치'

    # --- 2) 중복 등록은 늘어나지 않는다 (멱등) ---
    Add-RegisteredProject -Path 'C:\창의디자인캠프\연습' | Out-Null
    Assert-Eq (@(Get-RegisteredProjects)).Count 1 '같은 경로 재등록은 무시'

    # --- 3) 두 번째 팀 폴더 추가 ---
    Add-RegisteredProject -Path 'C:\창의디자인캠프\03조_지구지킴이' | Out-Null
    Assert-Eq (@(Get-RegisteredProjects)).Count 2 '다른 경로는 추가됨'

    # --- 4) 기존 앱 상태(실측 형태)를 깨지 않는다 ---
    $existing = @{
        'notification' = '{"list":[]}'
        'server' = '{"list":[],"projects":{"local":[{"worktree":"C:\\Users\\user\\Documents\\Default Project","expanded":true}]}}'
        'model' = '{"user":[{"modelID":"deepseek-v4-flash","providerID":"deepseek"}]}'
    }
    $globalPath = Join-Path $tmp 'opencode.global.dat'
    ($existing | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $globalPath -Encoding utf8

    Add-RegisteredProject -Path 'C:\창의디자인캠프\07조_별빛' | Out-Null
    $after = @(Get-RegisteredProjects)
    Assert-True ($after -contains 'C:\Users\user\Documents\Default Project') '기존 프로젝트가 보존됨'
    Assert-True ($after -contains 'C:\창의디자인캠프\07조_별빛') '새 프로젝트가 추가됨'

    $raw = Get-Content -LiteralPath $globalPath -Raw -Encoding UTF8
    Assert-Contains $raw 'deepseek-v4-flash' '다른 키(model)가 보존됨'
    Assert-Contains $raw 'notification' '다른 키(notification)가 보존됨'

    # --- 5) 온보딩 건너뛰기 ---
    Set-OnboardingComplete | Out-Null
    $settings = Get-Content -LiteralPath (Join-Path $tmp 'opencode.settings') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $settings.firstLaunchOnboardingComplete $true '온보딩 완료 플래그가 설정됨'

    # --- 6) 기존 settings 의 다른 키를 보존한다 ---
    $s = @{ 'windowIds' = @('abc-123'); 'tauriMigrated' = $true }
    ($s | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $tmp 'opencode.settings') -Encoding utf8
    Set-OnboardingComplete | Out-Null
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
