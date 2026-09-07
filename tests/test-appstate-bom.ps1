$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-appstate.ps1"

# 앱 상태 파일에 BOM 이 붙으면 앱이 창을 못 만든다.
#
# 실측 사고 (student 계정, 2026-09-01):
#   PowerShell 5.1 의 `Set-Content -Encoding utf8` 은 EF BB BF 를 붙인다.
#   우리가 읽을 때는 Get-Content -Encoding UTF8 이 BOM 을 떼주므로
#   테스트가 전부 통과했다. 앱만 죽었다.
#
#   앱은 electron-store 로 읽는데 clearInvalidConfig 기본값이 false 라
#   JSON.parse 의 SyntaxError 를 그대로 던진다. 생성자가 곧바로
#   this.store 를 읽으므로 앱이 창을 만들기 전에 멈춘다.
#
#   실측 A/B (OpenCode.exe 직접 실행):
#     BOM 있음 -> 프로세스 3개, 창 0개
#     BOM 없음 -> 프로세스 6개, 창 1개 (제목 "OpenCode")
#   학생은 "캠프 시작" 을 눌러도 아무 일도 안 일어난다.

$tmp = Join-Path $env:TEMP ("campbom-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$env:CAMP_APPSTATE_DIR = $tmp

function Get-앞3바이트([string]$Path) {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 3
        $n = $fs.Read($buf, 0, 3)
        if ($n -lt 3) { return '' }
        return ('{0:x2} {1:x2} {2:x2}' -f $buf[0], $buf[1], $buf[2])
    } finally { $fs.Dispose() }
}

try {
    $settings = Join-Path $tmp 'opencode.settings'
    $global   = Join-Path $tmp 'opencode.global.dat'

    # --- 새로 만들 때 BOM 이 붙지 않는지 ---
    Assert-True (Set-OnboardingComplete) '온보딩 표시 저장 성공'
    Assert-FileExists $settings 'opencode.settings 만들어짐'
    Assert-True ((Get-앞3바이트 $settings) -ne 'ef bb bf') 'opencode.settings 에 BOM 없음'

    Assert-True (Add-RegisteredProject -Path 'C:\Users\test\내캠페인') '프로젝트 등록 성공'
    Assert-FileExists $global 'opencode.global.dat 만들어짐'
    Assert-True ((Get-앞3바이트 $global) -ne 'ef bb bf') 'opencode.global.dat 에 BOM 없음'

    # --- 이미 있는 파일에 덧쓸 때도 BOM 이 붙지 않는지 ---
    Assert-True (Add-RegisteredProject -Path 'C:\Users\test\연습') '두 번째 프로젝트 등록 성공'
    Assert-True ((Get-앞3바이트 $global) -ne 'ef bb bf') '덧쓴 뒤에도 BOM 없음'
    Assert-True (Set-OnboardingComplete) '온보딩 표시 다시 저장 성공'
    Assert-True ((Get-앞3바이트 $settings) -ne 'ef bb bf') '덧쓴 뒤에도 settings BOM 없음'

    # --- 앱과 똑같은 방식으로 읽어도 파싱되는지 ---
    # 앱은 BOM 을 떼주지 않는다. 그래서 BOM 을 떼지 않고 그대로 파싱해 본다.
    foreach ($f in @($settings, $global)) {
        $raw = [System.IO.File]::ReadAllText($f, (New-Object System.Text.UTF8Encoding($false)))
        $이름 = Split-Path -Leaf $f
        # 함정: String.StartsWith(string) 은 문화권 비교라 U+FEFF 를
        # 무시 문자로 보고 무엇에나 True 를 돌려준다. 문자 코드를 직접 본다.
        $첫코드 = if ($raw.Length -gt 0) { [int][char]$raw[0] } else { 0 }
        Assert-True ($첫코드 -ne 0xFEFF) ($이름 + ' 이 U+FEFF 로 시작하지 않음 (첫 문자 ' + $첫코드 + ')')
        $깨짐 = $false
        try { $null = $raw | ConvertFrom-Json } catch { $깨짐 = $true }
        Assert-True (-not $깨짐) ($이름 + ' 을 BOM 제거 없이 파싱 가능')
    }

    # --- 등록 내용이 실제로 들어갔는지 (BOM 만 고치고 기능이 깨지지 않았는지) ---
    $등록됨 = @(Get-RegisteredProjects)
    Assert-True ($등록됨 -contains 'C:\Users\test\내캠페인') '첫 프로젝트가 등록 목록에 있음'
    Assert-True ($등록됨 -contains 'C:\Users\test\연습') '두 번째 프로젝트가 등록 목록에 있음'

    # --- 소스에 Set-Content 가 다시 들어오지 않았는지 ---
    $src = Get-Content -LiteralPath "$Repo\dist\scripts\lib-appstate.ps1" -Raw -Encoding UTF8
    # 주석에는 "Set-Content 를 쓰지 마라" 라고 적혀 있으므로 실제 호출만 본다.
    Assert-NotContains $src '| Set-Content' 'lib-appstate 가 Set-Content 로 파일을 쓰지 않음 (BOM 이 붙는다)'
    Assert-NotContains $src 'Out-File' 'lib-appstate 가 Out-File 을 쓰지 않음 (BOM 이 붙는다)'
    Assert-Contains $src 'Write-JsonNoBom' 'lib-appstate 가 Write-JsonNoBom 을 씀'

    # --- 런처가 창 손잡이로 확인하는지 ---
    $lsrc = Get-Content -LiteralPath "$Repo\dist\scripts\launcher.ps1" -Raw -Encoding UTF8
    Assert-Contains $lsrc 'MainWindowHandle' '런처가 창 손잡이를 확인함'
    Assert-Contains $lsrc 'Test-AppOpened' '런처가 앱 열림을 확인하는 함수를 씀'
    Assert-NotContains $lsrc "Start-Process -FilePath `$app | Out-Null" '확인 없이 성공 보고하지 않음'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\CAMP_APPSTATE_DIR -ErrorAction SilentlyContinue
}

if (Test-Summary) { exit 0 } else { exit 1 }
