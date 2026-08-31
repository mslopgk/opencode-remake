# 리포의 camp-preset/ 와 template/ 를 dist/ 로 복사해 배포판을 완성한다.
# opencode 가 camp-preset 안에 만들어 둔 node_modules·package.json 은 제외한다.

function Invoke-BuildDist([string]$RepoDir) {
    $exclude = @('node_modules', 'package.json', 'package-lock.json', 'bun.lock', '.gitignore')

    $pairs = @(
        @{ Src = (Join-Path $RepoDir 'camp-preset'); Dst = (Join-Path $RepoDir 'dist\preset') },
        @{ Src = (Join-Path $RepoDir 'template');    Dst = (Join-Path $RepoDir 'dist\template') }
    )

    # 에이전트가 실행하는 도구들. 이게 학생 노트북에 없으면
    # /포스터·/음악·/영상·/합쳐줘 가 전부 실패한다 (실제로 겪음).
    $toolNames = @('camp-media.sh', 'merge-slides.sh', 'merge-slides.py', 'camp-publish.sh', 'media-gen.py')
    $toolDst = Join-Path $RepoDir 'dist\tools'
    if (Test-Path -LiteralPath $toolDst) { Remove-Item -Recurse -Force $toolDst }
    New-Item -ItemType Directory -Path $toolDst -Force | Out-Null
    foreach ($t in $toolNames) {
        $src = Join-Path $RepoDir ('scripts\' + $t)
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            Write-Host ('도구가 없습니다: ' + $src)
            return 1
        }
        Copy-Item -LiteralPath $src -Destination $toolDst -Force
    }

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
        'tools\camp-media.sh',
        'tools\merge-slides.sh',
        'tools\merge-slides.py',
        'tools\camp-publish.sh',
        'tools\media-gen.py',
        '설치하기.cmd',
        '점검하기.cmd',
        '캠프시작.cmd',
        '깃허브연결.cmd',
        'scripts\orchestrator.ps1',
        'scripts\selfcheck.ps1',
        'scripts\launcher.ps1',
        'scripts\lib-gui.ps1',
        'scripts\gui-install.ps1',
        'scripts\gui-check.ps1',
        'scripts\gui-launcher.ps1',
        'scripts\github-connect.ps1',
        'scripts\gui-github.ps1',
        'scripts\camp.ico',
        '창의디자인캠프 설치.exe',
        '캠프 시작.exe',
        '점검.exe',
        '깃허브 연결.exe'
    )
    $bundleFiles = @(
        'bundle\opencode-desktop-win-x64.exe',
        'bundle\opencode-windows-x64.zip',
        'bundle\node-lts-x64.msi',
        'bundle\python-3.12-amd64.exe',
        'bundle\Git-64-bit.exe',
        'bundle\CascadiaCode-NF.zip',
        'bundle\gh-windows-amd64.zip'
    )
    $secretFiles = @(
        'secrets\auth.json',
        'secrets\credentials.json',
        'secrets\config.json',
        'secrets\media-keys.env'
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
