$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"

# --- .ps1 은 UTF-8 BOM 이어야 한다 ---
# Windows PowerShell 5.1 은 BOM 이 없는 .ps1 을 ANSI 로 읽는다.
# 그러면 스크립트 안의 한국어 문자열이 통째로 깨진다(출력 인코딩만으로는 안 됨).

$targets = @()
foreach ($dir in @((Join-Path $Repo 'dist\scripts'), (Join-Path $Repo 'tests'), (Join-Path $Repo 'scripts'))) {
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $targets += Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -Recurse
    }
}

Assert-True ($targets.Count -gt 0) '검사할 .ps1 파일이 있음'

foreach ($f in $targets) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True $hasBom ('UTF-8 BOM: ' + $f.Name)
}

# --- .cmd 는 순수 ASCII 여야 한다 ---
# cmd.exe 는 UTF-8 배치 파일의 비ASCII 문자를 잘못 파싱한다.
# chcp 65001 을 넣어도 바이트 오프셋이 어긋나 명령이 쪼개진다(실측 확인).
# 그래서 학생이 읽는 한국어는 전부 PowerShell 쪽에 두고 .cmd 는 ASCII 로만 둔다.
$cmds = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter '*.cmd' -File -ErrorAction SilentlyContinue)
Assert-True ($cmds.Count -ge 3) '진입점 .cmd 가 3개 이상'

foreach ($cmd in $cmds) {
    $bytes = [System.IO.File]::ReadAllBytes($cmd.FullName)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 })
    Assert-Eq $nonAscii.Count 0 ('순수 ASCII: ' + $cmd.Name)

    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    Assert-Contains $text 'chcp 65001' ('콘솔 UTF-8 설정: ' + $cmd.Name)
    Assert-Contains $text 'ExecutionPolicy Bypass' ('실행정책 우회: ' + $cmd.Name)
}

if (Test-Summary) { exit 0 } else { exit 1 }
