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
    $toolNames = @('camp-media.sh', 'merge-slides.sh', 'merge-slides.py', 'camp-publish.sh', 'media-gen.py', 'camp-usage.sh')
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
        'tools\camp-usage.sh',
        '설치하기.cmd',
        '점검하기.cmd',
        '캠프시작.cmd',
        '깃허브연결.cmd',
        '발표자료보기.cmd',
        'scripts\orchestrator.ps1',
        'scripts\selfcheck.ps1',
        'scripts\launcher.ps1',
        'scripts\lib-uia.ps1',
        'scripts\lib-shellfix.ps1',
        'scripts\lib-gui.ps1',
        'scripts\gui-install.ps1',
        'scripts\gui-check.ps1',
        'scripts\gui-launcher.ps1',
        'scripts\github-connect.ps1',
        'scripts\gui-github.ps1',
        'scripts\slides-viewer.ps1',
        'scripts\camp.ico',
        '창의디자인캠프 설치.exe',
        '캠프 시작.exe',
        '점검.exe',
        '깃허브 연결.exe',
        '발표자료 보기.exe'
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
        'secrets\media-keys.env'
    )

    $missing = @()
    foreach ($r in ($required + $bundleFiles + $secretFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $DistDir $r))) { $missing += $r }
    }

    # 함정(실측 사고, 2026-09-05 현장): 맥에서 .sh 가 CRLF 면 bash 가 모든 줄
    # 끝에 캐리지리턴(CR)을 붙인다. CFG="$HOME/.config/opencode" 같은 줄이 그대로
    # "opencode<CR>" 폴더를 만들어서, 설정도 열쇠도 엉뚱한 곳으로 들어간다.
    # 학생 화면에는 "캠프 설정이 덜 들어갔어요 (도우미 0, 명령 0)" 만 뜬다.
    # 윈도우 git bash 는 LF 를 잘 읽으므로 전부 LF 로 통일한다.
    foreach ($ㅅ in @(Get-ChildItem -LiteralPath (Join-Path $DistDir 'tools') -File -ErrorAction SilentlyContinue)) {
        if ($ㅅ.Extension -notin @('.sh', '.py')) { continue }
        $바이트 = [System.IO.File]::ReadAllBytes($ㅅ.FullName)
        for ($i = 0; $i -lt $바이트.Length - 1; $i++) {
            if ($바이트[$i] -eq 13 -and $바이트[$i + 1] -eq 10) {
                $missing += ('tools\' + $ㅅ.Name + ' 이 윈도우 줄바꿈(CRLF)입니다. 맥에서 깨집니다.')
                break
            }
        }
    }

    # 함정(실측 사고, 2026-09-05): exe 는 불러올 스크립트 목록을 자기 안에
    # 박아 둔다. 스크립트를 새로 만들고 build-exe.ps1 을 안 돌리면 exe 는
    # 없는 함수를 부르다 죽는다. 창도 없어서 학생은 아무것도 못 본다.
    # 그래서 스크립트가 exe 보다 새것이면 빌드를 멈춘다.
    $exe목록 = @('창의디자인캠프 설치.exe','캠프 시작.exe','점검.exe','깃허브 연결.exe','발표자료 보기.exe')
    $가장오래된 = $null
    foreach ($e in $exe목록) {
        $f = Get-Item -LiteralPath (Join-Path $DistDir $e) -ErrorAction SilentlyContinue
        if ($null -eq $f) { continue }
        if ($null -eq $가장오래된 -or $f.LastWriteTime -lt $가장오래된) { $가장오래된 = $f.LastWriteTime }
    }
    if ($null -ne $가장오래된) {
        $새스크립트 = @(Get-ChildItem -LiteralPath (Join-Path $DistDir 'scripts') -Filter *.ps1 -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -gt $가장오래된 })
        if ($새스크립트.Count -gt 0) {
            $missing += ('실행파일이 낡았습니다. scripts\build-exe.ps1 을 먼저 실행하세요. (더 새로운 스크립트: ' +
                         (($새스크립트 | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', ') + ')')
        }
    }

    return @{ Ok = ($missing.Count -eq 0); Missing = $missing }
}

# 직접 실행되면 빌드한다 (dot-source 하면 함수만 불러온다)
if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $rc = Invoke-BuildDist -RepoDir $repo
    if ($rc -eq 0) {
        $v = Test-DistComplete -DistDir (Join-Path $repo 'dist')
        if (-not $v.Ok) {
            Write-Host '배포판이 아직 덜 됐습니다:'
            foreach ($m in $v.Missing) { Write-Host ('  - ' + $m) }
            exit 1
        }
        Write-Host '배포판 빌드 완료: dist\preset, dist\template'
    }
    exit $rc
}
