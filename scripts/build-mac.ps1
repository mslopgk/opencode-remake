# 맥 몫을 만든다.
#
# 맥은 "빌드" 라고 할 게 거의 없다. 컴파일하는 것이 하나도 없다.
# 두 가지를 모으는 일이 전부다.
#
#   1) 남이 만들어 배포하는 공식 파일  — 받아 온다 (인터넷 필요, 한 번만)
#        opencode 데스크탑 앱   .zip   (칩 종류별로 두 개)
#        opencode CLI           .zip   (두 개)
#        gh (깃허브 도구)       .zip   (두 개)
#        파이썬                 .pkg   (하나, 두 칩 겸용)
#      -> mac-bundle\ 에 모인다. 이미 있으면 다시 안 받는다.
#
#   2) 우리 것                  — dist\ 에서 꾸린다 (인터넷 불필요)
#        preset, tools, template, secrets, models.json
#      -> mac-bundle\camp-mac-payload.tar.gz 하나로 묶는다.
#
# 설치 절차 자체는 scripts\mac-install.sh 한 장이고, 그건 그냥 텍스트다.
# 맥에서 컴파일할 것이 없으므로 윈도우에서 전부 준비할 수 있다.
#
# 쓰는 법:
#   powershell -ExecutionPolicy Bypass -File scripts\build-mac.ps1
#
# 그 다음 lan-share\ 와 USB 로 복사하면 끝이다 (아래 마지막에 안내가 나온다).

$ErrorActionPreference = 'Stop'

# 앱 버전은 윈도우판과 반드시 같아야 한다.
# 다르면 학생마다 다른 앱을 쓰게 되고, 우리가 시험하지 않은 조합이 생긴다.
$앱버전 = 'v1.18.20'
$깃허브도구버전 = 'v2.100.0'
$파이썬버전 = '3.12.10'

function Get-CampMacFile {
    param([string]$Url, [string]$Dest)

    if (Test-Path -LiteralPath $Dest -PathType Leaf) {
        $mb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
        Write-Host ('  이미 있음: ' + (Split-Path -Leaf $Dest) + '  ' + $mb + ' MB')
        return $true
    }
    Write-Host ('  받는 중: ' + (Split-Path -Leaf $Dest))
    $임시 = $Dest + '.받는중'
    try {
        # 중간에 끊긴 파일을 진짜처럼 두면, 다음에 돌릴 때 "이미 있음" 으로
        # 넘어가서 학생 노트북에서야 깨진 것을 알게 된다. 다 받은 뒤에 이름을 준다.
        Invoke-WebRequest -Uri $Url -OutFile $임시 -UseBasicParsing
        Move-Item -LiteralPath $임시 -Destination $Dest -Force
        $mb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
        Write-Host ('    받음  ' + $mb + ' MB')
        return $true
    }
    catch {
        Remove-Item -LiteralPath $임시 -Force -ErrorAction SilentlyContinue
        Write-Host ('    실패: ' + $_.Exception.Message)
        return $false
    }
}

function Invoke-BuildMac {
    param([string]$RepoDir)

    $짐 = Join-Path $RepoDir 'mac-bundle'
    if (-not (Test-Path -LiteralPath $짐)) {
        New-Item -ItemType Directory -Path $짐 -Force | Out-Null
    }

    # --- 1) 공식 파일 받기 ---
    Write-Host '맥용 준비물을 확인하고 있습니다...'
    $앱뿌리 = 'https://github.com/anomalyco/opencode/releases/download/' + $앱버전
    $gh뿌리 = 'https://github.com/cli/cli/releases/download/' + $깃허브도구버전
    $py뿌리 = 'https://www.python.org/ftp/python/' + $파이썬버전

    $받을것 = @(
        @{ Url = ($앱뿌리 + '/opencode-desktop-mac-arm64.zip'); Name = 'opencode-desktop-mac-arm64.zip' },
        @{ Url = ($앱뿌리 + '/opencode-desktop-mac-x64.zip');   Name = 'opencode-desktop-mac-x64.zip' },
        @{ Url = ($앱뿌리 + '/opencode-darwin-arm64.zip');      Name = 'opencode-darwin-arm64.zip' },
        @{ Url = ($앱뿌리 + '/opencode-darwin-x64.zip');        Name = 'opencode-darwin-x64.zip' },
        @{ Url = ($gh뿌리 + '/gh_' + $깃허브도구버전.TrimStart('v') + '_macOS_arm64.zip'); Name = 'gh-macos-arm64.zip' },
        @{ Url = ($gh뿌리 + '/gh_' + $깃허브도구버전.TrimStart('v') + '_macOS_amd64.zip'); Name = 'gh-macos-amd64.zip' },
        @{ Url = ($py뿌리 + '/python-' + $파이썬버전 + '-macos11.pkg'); Name = ('python-' + $파이썬버전 + '-macos11.pkg') }
    )

    $못받음 = @()
    foreach ($ㅂ in $받을것) {
        if (-not (Get-CampMacFile -Url $ㅂ.Url -Dest (Join-Path $짐 $ㅂ.Name))) {
            $못받음 += $ㅂ.Name
        }
    }
    if ($못받음.Count -gt 0) {
        Write-Host ''
        Write-Host '다음을 못 받았습니다:'
        foreach ($m in $못받음) { Write-Host ('  - ' + $m) }
        Write-Host '인터넷을 확인하고 다시 실행하세요.'
        return 1
    }

    # --- 2) 우리 것 꾸리기 ---
    $dist = Join-Path $RepoDir 'dist'
    foreach ($ㅍ in @('preset', 'tools', 'template')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dist $ㅍ) -PathType Container)) {
            Write-Host ('dist\' + $ㅍ + ' 가 없습니다. build-dist.ps1 을 먼저 실행하세요.')
            return 1
        }
    }

    Write-Host '캠프 설정을 꾸리는 중...'
    $임시 = Join-Path $env:TEMP ('campmac-' + [guid]::NewGuid().ToString('N'))
    $안 = Join-Path $임시 'p'
    New-Item -ItemType Directory -Path $안 -Force | Out-Null
    try {
        foreach ($ㅍ in @('preset', 'tools', 'template')) {
            Copy-Item -LiteralPath (Join-Path $dist $ㅍ) -Destination (Join-Path $안 $ㅍ) -Recurse -Force
        }
        $비밀 = Join-Path $안 'secrets'
        New-Item -ItemType Directory -Path $비밀 -Force | Out-Null
        foreach ($ㅎ in @('auth.json', 'media-keys.env')) {
            $원 = Join-Path $dist ('secrets\' + $ㅎ)
            if (-not (Test-Path -LiteralPath $원 -PathType Leaf)) {
                Write-Host ('열쇠가 없습니다: ' + $원)
                return 1
            }
            Copy-Item -LiteralPath $원 -Destination $비밀 -Force
        }

        # 앱이 첫 실행 때 인터넷에서 받아오는 모델 목록. 미리 넣으면 4.5MB 를 아낀다.
        $모델 = Join-Path $env:USERPROFILE '.cache\opencode\models.json'
        if (Test-Path -LiteralPath $모델 -PathType Leaf) {
            Copy-Item -LiteralPath $모델 -Destination (Join-Path $안 'models.json') -Force
        }
        else {
            Write-Host '  주의: models.json 이 없습니다. 학생 맥이 그것만 따로 받게 됩니다.'
        }

        # tar 는 윈도우 10 1803 부터 기본으로 들어 있다.
        $꾸러미 = Join-Path $짐 'camp-mac-payload.tar.gz'
        # 반드시 윈도우가 품고 있는 tar 를 쓴다.
        # 그냥 'tar' 라고 쓰면 Git 이 딸려 보낸 tar 가 잡히는데, 그건 윈도우
        # 경로(C:\...)를 이스케이프해서 "Broken pipe" 로 죽는다(실측).
        $tar = Join-Path (Join-Path $env:SystemRoot 'System32') 'tar.exe'
        if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) {
            Write-Host 'tar.exe 가 없습니다 (윈도우 10 1803 이상 필요).'
            return 1
        }
        Push-Location $안
        try {
            & $tar -czf $꾸러미 .
            if ($LASTEXITCODE -ne 0) { Write-Host 'tar 로 묶지 못했습니다.'; return 1 }
        }
        finally { Pop-Location }

        $mb = [math]::Round((Get-Item $꾸러미).Length / 1MB, 2)
        Write-Host ('  camp-mac-payload.tar.gz  ' + $mb + ' MB')
    }
    finally {
        Remove-Item -LiteralPath $임시 -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host '맥 몫을 다 만들었습니다: mac-bundle\'
    Write-Host ''
    Write-Host '이제 내보내려면:'
    Write-Host '  내부망  ->  mac-bundle\*.zip, *.pkg 를 lan-share\mac\ 으로'
    Write-Host '              camp-mac-payload.tar.gz 와 scripts\mac-install.sh 는 lan-share\ 바로 밑으로'
    Write-Host '  USB     ->  같은 구조로 USB 루트에'
    Write-Host ''
    Write-Host '학생이 하는 것 (터미널 한 줄):'
    Write-Host '  내부망  curl -fsSL http://192.168.0.5/mac -o ~/camp.sh && bash ~/camp.sh'
    Write-Host '  USB     bash /Volumes/CAMP2026/mac-install.sh'
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    exit (Invoke-BuildMac -RepoDir $repo)
}
