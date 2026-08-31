# 팀 폴더를 만든다. scripts/new-team.sh 와 규칙이 같아야 한다
# (조번호 두 자리, 1~15, NN조_팀명, 자리표시자 치환).
# 학생 노트북에는 bash 가 없으므로 PowerShell 로 따로 구현한다.
#
# 인코딩 주의 — 요구가 정반대인 두 가지가 있다:
#   1) 이 .ps1 파일 자체는 UTF-8 "BOM 있음" 이어야 한다.
#      PowerShell 5.1 이 BOM 없는 .ps1 을 ANSI 로 읽어 한국어를 깨뜨린다.
#   2) 학생에게 써 주는 파일(index.html, 우리팀.md)은 UTF-8 "BOM 없음" 이어야 한다.
#      Set-Content -Encoding utf8 은 5.1 에서 BOM 을 붙이므로 쓰면 안 된다.
#      HTML 앞의 BOM 은 렌더링 문제를 일으킬 수 있고 bash 판과 바이트가 달라진다.

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-TeamFolderName([int]$Number, [string]$Name) {
    if ($Number -lt 1 -or $Number -gt 15) { return $null }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $bad = @('\', '/', ':', '*', '?', '"', '<', '>', '|')
    foreach ($ch in $bad) {
        if ($Name.Contains($ch)) { return $null }
    }
    return ('{0:D2}조_{1}' -f $Number, $Name)
}

# 바탕화면 경로를 구한다.
#
# $env:USERPROFILE\Desktop 을 쓰지 않는 이유: OneDrive 를 쓰는 노트북에서는
# 바탕화면이 OneDrive 안으로 옮겨져 있다. 그러면 학생 눈에 보이는 바탕화면과
# 우리가 만든 폴더의 위치가 어긋난다. Windows 에 직접 물어본다.
function Get-CampDesktop {
    try {
        $d = [Environment]::GetFolderPath('Desktop')
        if ($d -and (Test-Path -LiteralPath $d -PathType Container)) { return $d }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Desktop')
}

# 팀 정보를 묻지 않고 작업 폴더를 만든다. 위치는 **바탕화면**이다.
#
# 왜 묻지 않나: 초등학교 5학년에게 시작하자마자 칸 두 개를 채우게 하면
# 거기서 막힌다. 조 번호와 팀 이름은 도우미가 대화하다가 물어서
# 우리팀.md 에 적는다. 학생은 채팅 칸에 답만 하면 된다.
#
# 왜 바탕화면인가: 학생이 자기가 만든 것을 눈으로 찾을 수 있어야 한다.
# 사용자 폴더 깊은 곳에 두면 초등학생은 다시 찾아가지 못한다.
function New-WorkFolder([string]$Parent, [string]$TemplateDir) {
    if (-not (Test-Path -LiteralPath $TemplateDir -PathType Container)) { return $null }

    # $Parent 를 주면 그곳에 만든다 (시험·멘토용). 안 주면 바탕화면이다.
    if ([string]::IsNullOrWhiteSpace($Parent)) { $Parent = Get-CampDesktop }
    if (-not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $dir = Join-Path $Parent '내캠페인'

    # 이미 있으면 절대 덮어쓰지 않는다 — 학생 작업물이 들어 있다
    if (Test-Path -LiteralPath $dir -PathType Container) { return $dir }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $dir -Recurse -Force
    $assets = Join-Path $dir 'assets'
    if (-not (Test-Path -LiteralPath $assets)) {
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
    }
    return $dir
}

function New-TeamFolder([int]$Number, [string]$Name, [string]$Parent, [string]$TemplateDir) {
    $folder = Get-TeamFolderName -Number $Number -Name $Name
    if ($null -eq $folder) { return $null }
    if (-not (Test-Path -LiteralPath $TemplateDir -PathType Container)) { return $null }

    if (-not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $dir = Join-Path $Parent $folder

    # 이미 있으면 절대 덮어쓰지 않는다 — 학생 작업물이 들어 있을 수 있다
    if (Test-Path -LiteralPath $dir -PathType Container) { return $dir }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $dir -Recurse -Force
    $assets = Join-Path $dir 'assets'
    if (-not (Test-Path -LiteralPath $assets)) {
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
    }

    $pad = '{0:D2}' -f $Number

    $docPath = Join-Path $dir '우리팀.md'
    if (Test-Path -LiteralPath $docPath -PathType Leaf) {
        $doc = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8
        $doc = $doc.Replace('- 조 번호: (아직 안 정함)', ('- 조 번호: ' + $pad + '조'))
        $doc = $doc.Replace('- 팀 이름: (아직 안 정함)', ('- 팀 이름: ' + $Name))
        Write-Utf8NoBom -Path $docPath -Text $doc
    }

    $htmlPath = Join-Path $dir 'index.html'
    if (Test-Path -LiteralPath $htmlPath -PathType Leaf) {
        $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
        $html = $html.Replace('00조 팀이름', ($pad + '조 ' + $Name))
        Write-Utf8NoBom -Path $htmlPath -Text $html
    }

    return $dir
}
