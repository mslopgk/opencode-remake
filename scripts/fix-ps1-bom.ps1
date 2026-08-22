# dist/scripts, tests, scripts 안의 .ps1 을 UTF-8 BOM 으로 다시 저장한다.
#
# 왜 필요한가: Windows PowerShell 5.1 은 BOM 이 없는 .ps1 을 ANSI 로 읽는다.
# 그러면 스크립트 안의 한국어 문자열이 통째로 깨진다. 편집기가 BOM 없이
# 저장했다면 이 스크립트를 돌린다. tests/test-encoding.ps1 이 회귀를 막는다.
#
# node_modules 는 건드리지 않는다 (npm 셰임 파일).

$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$withBom = New-Object System.Text.UTF8Encoding($true)
$changed = 0

foreach ($rel in @('dist\scripts', 'tests', 'scripts')) {
    $dir = Join-Path $repo $rel
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -Recurse | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        if (-not $hasBom) {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            [System.IO.File]::WriteAllText($_.FullName, $text, $withBom)
            Write-Host ('BOM 추가: ' + $_.Name)
            $changed++
        }
    }
}

if ($changed -eq 0) { Write-Host '모든 .ps1 이 이미 UTF-8 BOM 입니다.' }
else { Write-Host ($changed.ToString() + '개 파일에 BOM 을 추가했습니다.') }
