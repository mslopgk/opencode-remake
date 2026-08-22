$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rc = 0
Get-ChildItem -Path (Join-Path $Repo 'tests') -Filter 'test-*.ps1' | ForEach-Object {
    Write-Host ""
    Write-Host ("=== " + $_.Name + " ===")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { $rc = 1 }
}
Write-Host ""
if ($rc -eq 0) { Write-Host "전체 통과" } else { Write-Host "실패 있음" -ForegroundColor Red }
exit $rc
