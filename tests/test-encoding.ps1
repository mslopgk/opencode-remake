$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"

# Windows PowerShell 5.1 은 BOM 이 없는 .ps1 을 ANSI 로 읽는다.
# 그러면 스크립트 안의 한국어가 통째로 깨진다(출력 인코딩만으로는 안 됨).
# 배포판·테스트의 모든 .ps1 은 UTF-8 BOM 이어야 한다.

$targets = @()
foreach ($dir in @((Join-Path $Repo 'dist\scripts'), (Join-Path $Repo 'tests'), (Join-Path $Repo 'scripts'))) {
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $targets += Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -Recurse
    }
}

Assert-True ($targets.Count -gt 0 ) '검사할 .ps1 파일이 있음'

foreach ($f in $targets) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True $hasBom ('UTF-8 BOM: ' + $f.Name)
}

# .cmd 진입점도 한국어를 담으므로 chcp 65001 이 있어야 한다
foreach ($cmd in (Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter '*.cmd' -File -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $cmd.FullName -Raw -Encoding UTF8
    Assert-Contains $text 'chcp 65001' ('콘솔 UTF-8 설정: ' + $cmd.Name)
}

if (Test-Summary) { exit 0 } else { exit 1 }
