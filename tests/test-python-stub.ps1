$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"
. "$Repo\dist\scripts\lib-team.ps1"
. "$Repo\dist\scripts\selfcheck.ps1"
. "$Repo\dist\scripts\orchestrator.ps1"

# 윈도우가 미리 심어 두는 껍데기 python.exe 에 속지 않는지 본다.
#
# 실측 사고 (student 계정, 2026-09-01):
#   %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe 는 파이썬이 아니라
#   마이크로소프트 스토어를 열어 주는 AppInstallerPythonRedirector.exe 다.
#   Get-Command 로 이름만 봤더니 "파이썬 이미 있어요" 로 넘어갔고,
#   그 계정에는 파이썬이 끝까지 안 깔렸다. 점검도 초록불이었다.
#   윈도우 노트북 전부가 이 껍데기를 갖고 있어서 학생 63명 전원에게 터진다.

$tmp = Join-Path $env:TEMP ("campstub-" + [guid]::NewGuid().ToString('N'))
$fakeApps = Join-Path $tmp 'WindowsApps'
$fakeReal = Join-Path $tmp 'real'
New-Item -ItemType Directory -Path $fakeApps -Force | Out-Null
New-Item -ItemType Directory -Path $fakeReal -Force | Out-Null

$원래경로 = $env:PATH
try {
    # --- 1. 소스 코드에 이름만 보는 검사가 남아 있지 않은지 ---
    $orch = Get-Content -LiteralPath "$Repo\dist\scripts\orchestrator.ps1" -Raw -Encoding UTF8
    Assert-NotContains $orch "Get-Command 'python.exe' -CommandType Application -ErrorAction SilentlyContinue))" `
        '파이썬을 이름만으로 판정하지 않음'
    Assert-Contains $orch 'Test-RealExe' 'orchestrator 가 Test-RealExe 를 씀'
    Assert-Contains $orch "'*\WindowsApps\*'" 'WindowsApps 경로를 걸러냄'

    $self = Get-Content -LiteralPath "$Repo\dist\scripts\selfcheck.ps1" -Raw -Encoding UTF8
    Assert-Contains $self 'Test-RealPython' '점검이 파이썬 실체를 확인함'
    Assert-Contains $self "'*\WindowsApps\*'" '점검도 WindowsApps 를 걸러냄'

    # --- 2. WindowsApps 안의 껍데기는 "없음" 으로 봐야 한다 ---
    # 성공하는 배치 파일을 껍데기 이름으로 둔다. 경로만으로 걸러져야 한다.
    "@echo off`r`nexit /b 0" | Set-Content -LiteralPath (Join-Path $fakeApps 'python.bat') -Encoding ascii
    $env:PATH = $fakeApps
    Assert-True (-not (Test-RealExe -Names @('python.bat') -Probe @('-c', 'pass'))) `
        'WindowsApps 경로에 있으면 실행되더라도 껍데기로 본다'

    # --- 3. WindowsApps 밖에 있고 실행이 안 되면 "없음" ---
    "@echo off`r`nexit /b 9009" | Set-Content -LiteralPath (Join-Path $fakeReal 'python.bat') -Encoding ascii
    $env:PATH = $fakeReal
    Assert-True (-not (Test-RealExe -Names @('python.bat') -Probe @('-c', 'pass'))) `
        '실행이 실패하면 없는 것으로 본다'

    # --- 4. WindowsApps 밖에 있고 실행되면 "있음" ---
    "@echo off`r`nexit /b 0" | Set-Content -LiteralPath (Join-Path $fakeReal 'python.bat') -Encoding ascii
    $env:PATH = $fakeReal
    Assert-True (Test-RealExe -Names @('python.bat') -Probe @('-c', 'pass')) `
        '실제로 실행되면 있는 것으로 본다'

    # --- 5. 앞 명령의 종료값이 남아 오판하지 않는지 ---
    $env:PATH = $fakeReal
    $global:LASTEXITCODE = 0
    "@echo off`r`nexit /b 1" | Set-Content -LiteralPath (Join-Path $fakeReal 'nope.bat') -Encoding ascii
    Assert-True (-not (Test-RealExe -Names @('nope.bat') -Probe @('-c', 'pass'))) `
        '이전 종료값 0 이 남아도 속지 않는다'

    # --- 6. 이 개발 기계의 진짜 파이썬은 찾아내야 한다 (거짓 실패 방지) ---
    $env:PATH = $원래경로
    Assert-True (Test-RealPython) '개발 기계의 진짜 파이썬은 찾아낸다'

    # --- 7. 설치 직후 PATH 갱신 ---
    # 파이썬 인스톨러는 레지스트리 Path 만 고친다. 이 프로세스의 $env:PATH 는
    # 옛 값이라, 바로 뒤에 도는 자체 점검이 거짓 빨간불을 낸다.
    $표시 = Join-Path $tmp '표시용'
    New-Item -ItemType Directory -Path $표시 -Force | Out-Null
    $env:PATH = $표시
    Update-CampPath
    $새PATH = @($env:PATH -split ';')
    Assert-True ($새PATH -contains $표시) 'PATH 갱신이 기존 항목을 잃지 않는다'
    Assert-True ($새PATH.Count -gt 1) 'PATH 갱신이 레지스트리 값을 읽어 온다'

    # 중복이 쌓이지 않는지 (여러 번 불러도 안전해야 한다)
    $한번 = @($env:PATH -split ';').Count
    Update-CampPath
    Update-CampPath
    Assert-Eq (@($env:PATH -split ';').Count) $한번 'PATH 갱신을 여러 번 해도 늘지 않는다'

    # --- 8. 설치·점검 단계에 "선생님을 불러 주세요" 가 없는지 ---
    # 설치는 집에서 혼자 한다. 부를 선생님이 없다.
    # (캠프 당일 단계 — 캠프 시작·그림·올리기 — 에는 그대로 있어야 맞다)
    foreach ($f in @('orchestrator.ps1', 'gui-install.ps1', 'gui-check.ps1')) {
        $내용 = Get-Content -LiteralPath "$Repo\dist\scripts\$f" -Raw -Encoding UTF8
        Assert-NotContains $내용 '선생님을 불러' ($f + ' 에는 선생님을 부르라는 말이 없음')
    }

}
finally {
    $env:PATH = $원래경로
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Assert-Failure 는 예외를 던지지 않는다. Test-Summary 로 종료값을 내야
# 실패가 조용히 통과로 보고되지 않는다.
if (Test-Summary) { exit 0 } else { exit 1 }
