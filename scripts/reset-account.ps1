# 한 계정을 "설치 전" 상태로 되돌린다. 다시 녹화하거나 실기기 재검증할 때 쓴다.
#
# 왜 필요한가: 설치는 되돌릴 수 없는 동작이 많다(글꼴 등록, 앱 설치,
# 바탕화면 아이콘). 한 번 깔린 계정에서는 "처음 깔 때 화면" 을 다시
# 볼 수 없어서 영상 촬영도 실기기 검증도 못 한다.
#
# 설계 원칙
#   1) 우리가 만든 것만 지운다. 계정의 다른 것은 손대지 않는다.
#   2) 지우기 전에 목록을 다 보여 준다.
#   3) 지키는 목록(-보호경로) 에 걸리면 무조건 멈춘다.
#      녹화 원본(Documents\oCam) 을 날린 적이 있어서 넣은 장치다.
#   4) 대상 계정이 로그온 중이면 거부한다. 파일이 잠겨 반쯤 지워진다.
#
# 쓰는 법
#   powershell -ExecutionPolicy Bypass -File scripts\reset-account.ps1 -계정 student
#   powershell -ExecutionPolicy Bypass -File scripts\reset-account.ps1 -계정 student -실행

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$계정,
    [switch]$실행
)

$ErrorActionPreference = 'Stop'

$프로필 = Join-Path 'C:\Users' $계정
if (-not (Test-Path -LiteralPath $프로필 -PathType Container)) {
    Write-Host ('그런 계정 폴더가 없습니다: ' + $프로필) -ForegroundColor Red
    exit 1
}

# --- 로그온 중이면 거부 ---
# 로그온 중이면 OpenCode.exe 가 떠 있어 파일이 잠긴다. 반쯤 지워진 계정은
# 깨끗한 계정보다 나쁘다. 안 깔린 것도 아니고 깔린 것도 아니게 된다.
$세션 = (query session 2>$null) -join "`n"
if ($세션 -match ('(?im)^\s*>?\S*\s+' + [regex]::Escape($계정) + '\s+\d+\s+Active')) {
    Write-Host ($계정 + ' 계정이 지금 로그온 중입니다.') -ForegroundColor Red
    Write-Host '그 계정에서 로그아웃한 뒤 다시 실행하세요.'
    exit 1
}

# --- 절대 건드리지 않는 것 ---
# 여기 걸리면 계산이 틀린 것이므로 지우지 않고 멈춘다.
$보호 = @(
    'Documents\oCam',                  # 녹화 원본. 실제로 날릴 뻔했다.
    'AppData\Roaming\oCam',
    '.claude', '.claude.json',
    '.cache\claude', '.local\bin', '.local\share\claude', '.local\state',
    '.config\git',
    'Desktop\desktop.ini', 'Downloads\desktop.ini', 'Documents\desktop.ini'
)

function Test-보호됨([string]$상대) {
    foreach ($b in $보호) {
        if ($상대 -eq $b) { return $true }
        if ($상대.StartsWith($b + '\')) { return $true }
    }
    return $false
}

# --- 지울 것 ---
# 인스톨러가 만드는 것 전부. orchestrator.ps1 의 설치 대상과 짝을 맞춘다.
$지울폴더 = @(
    'AppData\Local\Programs\@opencode-aidesktop',
    'AppData\Local\Programs\opencode-cli',
    'AppData\Local\Programs\gh-cli',
    'AppData\Local\Programs\camp-tools',
    'AppData\Local\@opencode-aidesktop-updater',
    'AppData\Local\창의디자인캠프-설치',
    'AppData\Local\npm-cache',
    'AppData\Local\GitHub CLI',
    'AppData\Roaming\ai.opencode.desktop',
    'AppData\Roaming\GitHub CLI',
    '.config\camp',
    '.config\opencode',
    '.local\share\opencode',
    '.cache\opencode',
    '창의디자인캠프',
    'Desktop\내캠페인'
)

# 와일드카드로 찾는 것들
$지울무늬 = @(
    '.config\opencode.backup-*',
    'AppData\Local\Microsoft\Windows\Fonts\CaskaydiaCove*',
    'AppData\Local\Microsoft\Windows\Fonts\Cascadia*',
    'Desktop\*.lnk',
    'Downloads\창의디자인캠프 설치*.exe',
    'Downloads\camp2026-setup*.exe'
)

$대상 = @()
foreach ($r in $지울폴더) {
    $p = Join-Path $프로필 $r
    if (Test-Path -LiteralPath $p) { $대상 += @{ 상대 = $r; 전체 = $p } }
}
foreach ($m in $지울무늬) {
    $부모 = Join-Path $프로필 (Split-Path -Parent $m)
    if (-not (Test-Path -LiteralPath $부모)) { continue }
    Get-ChildItem -LiteralPath $부모 -Filter (Split-Path -Leaf $m) -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $상대 = $_.FullName.Substring($프로필.Length).TrimStart('\')
            $대상 += @{ 상대 = $상대; 전체 = $_.FullName }
        }
}

# --- 보호 검사 ---
$사고 = @()
foreach ($t in $대상) { if (Test-보호됨 $t.상대) { $사고 += $t.상대 } }
if ($사고.Count -gt 0) {
    Write-Host '지키는 목록에 걸렸습니다. 아무것도 지우지 않고 멈춥니다.' -ForegroundColor Red
    foreach ($s in $사고) { Write-Host ('  ' + $s) }
    exit 1
}

if ($대상.Count -eq 0) {
    Write-Host ($계정 + ' 계정은 이미 설치 전 상태입니다. 지울 것이 없습니다.')
    exit 0
}

Write-Host ''
Write-Host ('=== ' + $계정 + ' 계정에서 지울 것 (' + $대상.Count + '개) ===')
foreach ($t in $대상) {
    $크기 = ''
    try {
        $i = Get-Item -LiteralPath $t.전체 -Force
        if ($i.PSIsContainer) {
            $b = (Get-ChildItem -LiteralPath $t.전체 -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
            if ($null -eq $b) { $b = 0 }
        } else { $b = $i.Length }
        $크기 = '  (' + [math]::Round($b / 1MB, 1) + ' MB)'
    } catch { }
    Write-Host ('  ' + $t.상대 + $크기)
}
Write-Host ''
Write-Host '=== 손대지 않는 것 ==='
foreach ($b in $보호) {
    $p = Join-Path $프로필 $b
    if (Test-Path -LiteralPath $p) { Write-Host ('  ' + $b) }
}
Write-Host ''

if (-not $실행) {
    Write-Host '지금은 목록만 보여 준 것입니다. 실제로 지우려면 -실행 을 붙이세요.' -ForegroundColor Yellow
    exit 0
}

$실패 = @()
foreach ($t in $대상) {
    try {
        Remove-Item -LiteralPath $t.전체 -Recurse -Force -ErrorAction Stop
        Write-Host ('  지움  ' + $t.상대)
    } catch {
        $실패 += ($t.상대 + ' — ' + $_.Exception.Message)
        Write-Host ('  실패  ' + $t.상대) -ForegroundColor Red
    }
}

Write-Host ''
if ($실패.Count -gt 0) {
    Write-Host '못 지운 것이 있습니다:' -ForegroundColor Red
    foreach ($f in $실패) { Write-Host ('  ' + $f) }
    Write-Host '그 계정이 로그온 중이거나 프로그램이 떠 있을 수 있습니다.'
    exit 1
}

# --- 레지스트리 안내 ---
# 다른 계정의 HKCU 는 관리자 권한 없이 못 건드린다. 대신 글꼴 검사가
# "등록이 가리키는 파일이 실제로 있는지" 까지 보도록 고쳐 뒀으므로,
# 파일만 지워도 다시 설치된다. (orchestrator.ps1 의 font 검사 참고)
Write-Host ($계정 + ' 계정을 설치 전 상태로 되돌렸습니다.') -ForegroundColor Green
Write-Host ''
Write-Host '다음에 할 일'
Write-Host ('  1) ' + $계정 + ' 계정으로 로그인')
Write-Host '  2) 다운로드 폴더의 "창의디자인캠프 설치" 를 두 번 누르기'
Write-Host '  3) 처음 깔 때 화면이 그대로 나옵니다'
exit 0
