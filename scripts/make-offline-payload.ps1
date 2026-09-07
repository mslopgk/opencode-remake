# 인터넷 없이 설치할 수 있게, 앱이 첫 실행 때 받아오는 것들을 짐으로 만든다.
#
# 왜 필요한가 (실측, 2026-09-05 행사장):
#   설치 파일 362MB 는 내부망으로 뿌리면 되는데, 앱이 처음 켤 때
#   바깥 인터넷에서 또 70MB 를 받아온다.
#     ~/.cache/opencode/models.json      4.5MB
#     ~/.cache/opencode/bin/rg.exe       4.2MB
#     ~/.config/opencode/node_modules   61MB
#   60명이면 4GB 다. 들어오는 회선이 100Mbps 라 그대로 죽는다.
#
#   그래서 이미 잘 돌아가는 이 컴퓨터의 것을 그대로 떠서 짐에 넣는다.
#
# 무엇을 안 넣는가:
#   설정(agent, command, skills, opencode.json)은 프리셋이 따로 넣는다.
#   여기 넣으면 두 군데서 같은 파일을 만들어 서로 엇갈린다.
#   auth.json 도 넣지 않는다. 그건 secrets 가 담당한다.

$ErrorActionPreference = 'Stop'

function New-CampOfflinePayload {
    param([string]$RepoDir)

    $짐 = Join-Path $RepoDir 'dist\offline'
    if (Test-Path -LiteralPath $짐) { Remove-Item -LiteralPath $짐 -Recurse -Force }
    New-Item -ItemType Directory -Path $짐 -Force | Out-Null

    $임시 = Join-Path $env:TEMP ('camp-offline-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $임시 -Force | Out-Null

    try {
        # --- 1) 캐시 (모델 목록 + 검색 도구) ---
        $캐시원본 = Join-Path $env:USERPROFILE '.cache\opencode'
        $캐시담을곳 = Join-Path $임시 'cache'
        New-Item -ItemType Directory -Path $캐시담을곳 -Force | Out-Null

        $models = Join-Path $캐시원본 'models.json'
        if (-not (Test-Path -LiteralPath $models -PathType Leaf)) {
            throw "models.json 이 없습니다. 이 컴퓨터에서 앱을 한 번 켜서 받아 두세요: $models"
        }
        Copy-Item -LiteralPath $models -Destination $캐시담을곳 -Force

        $rg = Join-Path $캐시원본 'bin\rg.exe'
        if (Test-Path -LiteralPath $rg -PathType Leaf) {
            $b = Join-Path $캐시담을곳 'bin'
            New-Item -ItemType Directory -Path $b -Force | Out-Null
            Copy-Item -LiteralPath $rg -Destination $b -Force
        }
        else {
            Write-Host '  주의: rg.exe 가 없습니다. 학생 컴퓨터가 이것만 따로 받게 됩니다.'
        }

        Compress-Archive -Path (Join-Path $캐시담을곳 '*') `
                         -DestinationPath (Join-Path $짐 'opencode-cache.zip') `
                         -CompressionLevel Optimal

        # --- 2) 플러그인 꾸러미 ---
        $설정원본 = Join-Path $env:USERPROFILE '.config\opencode'
        $설정담을곳 = Join-Path $임시 'config'
        New-Item -ItemType Directory -Path $설정담을곳 -Force | Out-Null

        $nm = Join-Path $설정원본 'node_modules'
        if (-not (Test-Path -LiteralPath $nm -PathType Container)) {
            throw "node_modules 가 없습니다. 이 컴퓨터에서 앱을 한 번 켜 두세요: $nm"
        }
        Copy-Item -LiteralPath $nm -Destination $설정담을곳 -Recurse -Force
        foreach ($f in @('package.json', 'package-lock.json')) {
            $원 = Join-Path $설정원본 $f
            if (Test-Path -LiteralPath $원 -PathType Leaf) {
                Copy-Item -LiteralPath $원 -Destination $설정담을곳 -Force
            }
        }

        Compress-Archive -Path (Join-Path $설정담을곳 '*') `
                         -DestinationPath (Join-Path $짐 'opencode-config.zip') `
                         -CompressionLevel Optimal

        foreach ($z in (Get-ChildItem -LiteralPath $짐 -Filter *.zip)) {
            Write-Host ('  ' + $z.Name + '  ' + [math]::Round($z.Length / 1MB, 1) + ' MB')
        }
        return 0
    }
    finally {
        Remove-Item -LiteralPath $임시 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    Write-Host '오프라인 짐을 만들고 있습니다...'
    exit (New-CampOfflinePayload -RepoDir $repo)
}
