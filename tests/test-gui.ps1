$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\lib-gui.ps1"

# ── 큐: 컬렉션 unroll 함정 회귀 검사 ──────────────────────────────────────────
# PowerShell 은 함수가 반환한 컬렉션을 파이프라인에서 풀어헤친다.
# 빈 Queue 를 그냥 return 하면 호출한 쪽이 $null 을 받는다 — 실제로 겪은 버그.
$q = New-CampQueue
Assert-True ($null -ne $q) 'New-CampQueue 가 null 을 반환하지 않음'
Assert-Eq $q.GetType().Name 'SynchronizedQueue' '동기화된 Queue 를 반환'
$q.Enqueue('a')
Assert-Eq $q.Count 1 '큐에 넣으면 개수가 늘어남'

$shared = New-CampShared
Assert-True ($null -ne $shared.Queue) 'Shared.Queue 가 null 이 아님'
$shared.Queue.Enqueue('x')
Assert-Eq $shared.Queue.Count 1 'Shared.Queue 가 동작함'
Assert-Eq $shared.Done $false 'Shared.Done 초기값'

# ── 로그 싱크 ────────────────────────────────────────────────────────────────
$sinkQ = New-CampQueue
Set-CampLogSink { param($level, $msg) $sinkQ.Enqueue(@{ level = $level; msg = $msg }) }
Write-Ok '완료 메시지'
Write-Step '진행 메시지'
Write-Fail '실패 메시지'
Write-Note '안내 메시지'
Clear-CampLogSink
Assert-Eq $sinkQ.Count 4 '싱크가 네 종류를 모두 받음'
$levels = @()
while ($sinkQ.Count -gt 0) { $levels += $sinkQ.Dequeue().level }
Assert-Eq ($levels -join ',') 'ok,step,fail,note' '레벨이 올바르게 전달됨'

# 싱크를 지우면 다시 콘솔로 간다 (예외 없이 동작해야 한다)
Write-Ok '싱크 없이도 동작' | Out-Null
Assert-True $true '싱크 해제 후에도 예외 없음'

# ── 테마: 발표자료와 같은 계열이어야 한다 ────────────────────────────────────
$t = Get-CampTheme
$tpl = Get-Content -LiteralPath (Join-Path $Repo 'template\index.html') -Raw -Encoding UTF8
foreach ($pair in @(@{ K = 'Bg'; V = '0b2545' }, @{ K = 'Accent'; V = '5bc0eb' }, @{ K = 'Sub'; V = 'a8dadc' })) {
    Assert-Eq $t[$pair.K].ToLower() ('#' + $pair.V) ('테마 색 ' + $pair.K)
    Assert-Contains $tpl.ToLower() ('#' + $pair.V) ('발표자료 ocean 테마에 같은 색 존재: ' + $pair.V)
}

# ── GUI 스크립트가 문법적으로 유효하고 함수를 정의하는가 ─────────────────────
$guiFiles = @(
    @{ File = 'gui-install.ps1';  Func = 'Show-CampInstaller' },
    @{ File = 'gui-check.ps1';    Func = 'Show-CampChecker' },
    @{ File = 'gui-launcher.ps1'; Func = 'Show-CampLauncher' }
)
foreach ($g in $guiFiles) {
    $path = Join-Path $Repo ('dist\scripts\' + $g.File)
    Assert-FileExists $path ('GUI 파일 존재: ' + $g.File)
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs) | Out-Null
    Assert-Eq $errs.Count 0 ('문법 오류 없음: ' + $g.File)
    $src = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    Assert-Contains $src ('function ' + $g.Func) ('함수 정의: ' + $g.Func)
    # dot-source 시 $MyInvocation.MyCommand.Path 는 null 이다(실측). 쓰면 안 된다
    Assert-NotContains $src 'Split-Path -Parent $MyInvocation.MyCommand.Path' ('MyInvocation 미사용: ' + $g.File)
    Assert-Contains $src '$PSScriptRoot' ('PSScriptRoot 사용: ' + $g.File)
}

# ── 아이콘 ───────────────────────────────────────────────────────────────────
$ico = Join-Path $Repo 'dist\scripts\camp.ico'
Assert-FileExists $ico '아이콘 파일 존재'
$b = [System.IO.File]::ReadAllBytes($ico)
Assert-Eq $b[0] 0 'ICO 헤더 reserved'
Assert-Eq $b[2] 1 'ICO 타입이 아이콘'
$count = [int]$b[4] + ([int]$b[5] * 256)
Assert-True ($count -ge 5) ('아이콘에 여러 크기가 담김 (' + $count + '개)')

# ── 진입점 exe ───────────────────────────────────────────────────────────────
foreach ($n in @('창의디자인캠프 설치.exe', '캠프 시작.exe', '점검.exe')) {
    $p = Join-Path $Repo ('dist\' + $n)
    Assert-FileExists $p ('진입점 exe 존재: ' + $n)
    if (Test-Path -LiteralPath $p) {
        $sz = (Get-Item $p).Length
        Assert-True ($sz -gt 8KB -and $sz -lt 200KB) ('exe 크기가 합리적: ' + $n)
    }
}

# .cmd 백업 경로도 남아 있어야 한다 (SmartScreen 대비)
foreach ($n in @('설치하기.cmd', '캠프시작.cmd', '점검하기.cmd')) {
    Assert-FileExists (Join-Path $Repo ('dist\' + $n)) ('백업 진입점 유지: ' + $n)
}

# ── build-exe 의 대상이 실제 함수를 가리키는가 ───────────────────────────────
. "$Repo\scripts\build-exe.ps1"
$targets = Get-ExeTargets
Assert-Eq $targets.Count 3 'exe 대상 3개'
foreach ($tg in $targets) {
    foreach ($f in ($tg.Load -split ',')) {
        Assert-FileExists (Join-Path $Repo ('dist\scripts\' + $f)) ('로드 대상 존재: ' + $f)
    }
}

if (Test-Summary) { exit 0 } else { exit 1 }
