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
    $files = @('opencode-desktop-win-x64.exe','opencode-windows-x64.zip','node-lts-x64.msi','python-3.12-amd64.exe','Git-64-bit.exe','CascadiaCode-NF.zip')
    foreach ($f in $files) {
        'fake' | Set-Content -LiteralPath (Join-Path $bundle $f) -Encoding utf8
    }

    # --- 설치 계획 ---
    $plan = @(Get-InstallPlan -BundleDir $bundle)
    Assert-True ($plan.Count -ge 6) '설치 계획에 6단계 이상'
    $names = @()
    foreach ($s in $plan) { $names += $s.Name }
    $joined = ($names -join '|')
    Assert-Contains $joined '노드' '계획에 Node 포함'
    Assert-Contains $joined '파이썬' '계획에 Python 포함'
    Assert-Contains $joined 'Git' '계획에 Git 포함'
    Assert-Contains $joined '글꼴' '계획에 글꼴 포함'
    Assert-Contains $joined '앱' '계획에 데스크탑 앱 포함'
    Assert-Contains $joined '점검용 도구' '계획에 standalone CLI 포함(자체 점검에 필요)'
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

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:CAMP_APPSTATE_DIR 'opencode.global.dat'))) 'DryRun 은 앱 상태를 건드리지 않음'

    # --- 번들 파일이 없으면 계획에서 제외된다 ---
    Remove-Item -LiteralPath (Join-Path $bundle 'node-lts-x64.msi') -Force
    $plan2 = @(Get-InstallPlan -BundleDir $bundle)
    $names2 = @()
    foreach ($s in $plan2) { $names2 += $s.Name }
    Assert-NotContains ($names2 -join '|') '노드' '없는 번들 파일은 계획에서 빠짐'

    # --- 사전 점검 ---
    $pre = Test-Prerequisites
    Assert-True ($null -ne $pre.Ok) '사전 점검이 결과를 반환'
    Assert-True ($null -ne $pre.Reasons) '사전 점검이 사유 목록을 반환'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
