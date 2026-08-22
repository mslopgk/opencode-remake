# 리포의 camp-preset/ 와 template/ 를 dist/ 로 복사해 배포판을 완성한다.
# opencode 가 camp-preset 안에 만들어 둔 node_modules·package.json 은 제외한다.

function Invoke-BuildDist([string]$RepoDir) {
    $exclude = @('node_modules', 'package.json', 'package-lock.json', 'bun.lock', '.gitignore')

    $pairs = @(
        @{ Src = (Join-Path $RepoDir 'camp-preset'); Dst = (Join-Path $RepoDir 'dist\preset') },
        @{ Src = (Join-Path $RepoDir 'template');    Dst = (Join-Path $RepoDir 'dist\template') }
    )

    foreach ($p in $pairs) {
        if (-not (Test-Path -LiteralPath $p.Src -PathType Container)) {
            Write-Host ('원본이 없습니다: ' + $p.Src)
            return 1
        }
        if (Test-Path -LiteralPath $p.Dst) { Remove-Item -Recurse -Force $p.Dst }
        New-Item -ItemType Directory -Path $p.Dst -Force | Out-Null

        Get-ChildItem -LiteralPath $p.Src -Force | Where-Object {
            $exclude -notcontains $_.Name
        } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $p.Dst -Recurse -Force
        }
    }
    return 0
}

function Test-DistComplete([string]$DistDir) {
    $required = @(
        'preset\AGENTS.md',
        'preset\opencode.json',
        'template\index.html',
        'template\우리팀.md',
        'template\slides',
        'preset\command\합쳐줘.md',
        '설치하기.cmd',
        '점검하기.cmd',
        '캠프시작.cmd',
        'scripts\orchestrator.ps1',
        'scripts\selfcheck.ps1',
        'scripts\launcher.ps1'
    )
    $bundleFiles = @(
        'bundle\opencode-desktop-win-x64.exe',
        'bundle\opencode-windows-x64.zip',
        'bundle\node-lts-x64.msi',
        'bundle\python-3.12-amd64.exe',
        'bundle\Git-64-bit.exe',
        'bundle\CascadiaCode-NF.zip'
    )
    $secretFiles = @(
        'secrets\auth.json',
        'secrets\credentials.json',
        'secrets\config.json'
    )

    $missing = @()
    foreach ($r in ($required + $bundleFiles + $secretFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $DistDir $r))) { $missing += $r }
    }
    return @{ Ok = ($missing.Count -eq 0); Missing = $missing }
}

# 직접 실행되면 빌드한다 (dot-source 하면 함수만 불러온다)
if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $rc = Invoke-BuildDist -RepoDir $repo
    if ($rc -eq 0) { Write-Host '배포판 빌드 완료: dist\preset, dist\template' }
    exit $rc
}
