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
# 이 시험은 설치 흐름을 보는 것이다. 개발 PC 의 남은 공간 때문에
# 흐름 검사가 실패하면 안 된다. 공간 검사 자체는 아래에서 따로 본다.
$env:CAMP_MIN_FREE_GB = '0.01'
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

    # --- 이미 설치된 구성요소는 건너뛴다 (멱등성) ---
    # 앞 단계에서 지운 node msi 를 되살린다
    'fake' | Set-Content -LiteralPath (Join-Path $bundle 'node-lts-x64.msi') -Encoding utf8
    $planNow = @(Get-InstallPlan -BundleDir $bundle)
    $nodeStep = $planNow | Where-Object { $_.File -eq 'node-lts-x64.msi' } | Select-Object -First 1
    Assert-True ($null -ne $nodeStep) '계획에 노드 단계가 있음'
    Assert-True ($null -ne $nodeStep.AlreadyInstalled) 'AlreadyInstalled 플래그가 채워짐'

    # 강제 설치 모드에서는 건너뛰지 않는다
    $env:CAMP_FORCE_INSTALL_ALL = '1'
    $planForce = @(Get-InstallPlan -BundleDir $bundle)
    foreach ($s in $planForce) {
        Assert-Eq $s.AlreadyInstalled $false ('강제 모드에서는 재설치: ' + $s.File)
    }
    Remove-Item Env:\CAMP_FORCE_INSTALL_ALL -ErrorAction SilentlyContinue

    # --- 사전 점검 ---
    $pre = Test-Prerequisites
    Assert-True ($null -ne $pre.Ok) '사전 점검이 결과를 반환'
    Assert-True ($null -ne $pre.Reasons) '사전 점검이 사유 목록을 반환'

    # 디스크 요구량이 과하지 않아야 한다.
    # 5GB 를 요구했더니 거의 찬 노트북에서 이유 없이 막혔다(실측).
    # 번들 350MB + 설치 약 1.5GB 이므로 2.5GB 가 상한이다.
    $orchSrc = Get-Content -LiteralPath (Join-Path $Repo 'dist\scripts\orchestrator.ps1') -Raw -Encoding UTF8
    Assert-Contains $orchSrc '$needGb = 2.5' '디스크 요구량이 2.5GB'
    Assert-NotContains $orchSrc '-lt 5GB' '5GB 요구가 남아 있지 않음'
    # 공간 부족 메시지는 반올림하지 않는다 (4.97GB 가 "5GB" 로 보이면 모순이 된다)
    Assert-Contains $orchSrc '[math]::Floor($free / 1GB * 10)' '남은 공간을 내림으로 표시'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}

# ── 바탕화면 바로가기 ────────────────────────────────────────────
# 실측 사고: ZIP 을 바탕화면에 풀던 방식에서 exe 자동해제 방식으로 바꿀 때
# 이 단계를 빼먹었다. 설치 파일이 %LOCALAPPDATA% 에 풀리므로 학생은
# 아무것도 찾을 수 없었다. 다른 사용자 계정에서 녹화하다 발견했다.
$orch = Get-Content -LiteralPath (Join-Path $Repo 'dist\scripts\orchestrator.ps1') -Raw -Encoding UTF8

Assert-True ($orch -match 'function New-CampShortcuts') '바로가기 만드는 함수가 있다'
Assert-True ($orch -match "GetFolderPath\('Desktop'\)") 'OneDrive 를 고려해 Windows 에 바탕화면 경로를 물어본다'
Assert-True ($orch -match 'WScript.Shell') '바로가기를 실제로 만든다'
Assert-True ($orch -match '바탕화면에 아이콘을 놓고 있어요') '설치 흐름에서 호출한다'

# 학생이 눌러야 하는 것이 다 있는지
foreach ($n in @('캠프 시작.exe', '발표자료 보기.exe', '점검.exe', '창의디자인캠프 설치.exe', '깃허브 연결.exe')) {
    Assert-True ($orch -match [regex]::Escape($n)) ('바로가기 대상에 포함: ' + $n)
}

# 실패해도 설치를 중단하지 않는다 (아이콘이 없어도 프로그램은 동작한다)
Assert-True ($orch -match '바탕화면에 아이콘을 놓지 못했어요') '실패 시 안내만 하고 계속한다'

if (Test-Summary) { exit 0 } else { exit 1 }
