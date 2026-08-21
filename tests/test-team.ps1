$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-team.ps1"

$Template = Join-Path $Repo 'template'
$tmp = Join-Path $env:TEMP ("campteam-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    # --- 이름 정규화 ---
    Assert-Eq (Get-TeamFolderName -Number 3 -Name '지구지킴이') '03조_지구지킴이' '조번호 두 자리 정규화'
    Assert-Eq (Get-TeamFolderName -Number 15 -Name '별빛') '15조_별빛' '15조 허용'
    Assert-Eq (Get-TeamFolderName -Number 0 -Name '팀') $null '0조는 거부'
    Assert-Eq (Get-TeamFolderName -Number 16 -Name '팀') $null '16조는 거부'
    Assert-Eq (Get-TeamFolderName -Number 3 -Name 'a\b') $null '경로 문자 포함은 거부'
    Assert-Eq (Get-TeamFolderName -Number 3 -Name '') $null '빈 이름은 거부'

    # --- 폴더 생성 ---
    $dir = New-TeamFolder -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template
    Assert-True ($null -ne $dir) '팀 폴더 생성 성공'
    Assert-Contains $dir '03조_지구지킴이' '경로에 팀 폴더명 포함'
    Assert-FileExists (Join-Path $dir 'index.html') 'index.html 복사됨'
    Assert-FileExists (Join-Path $dir '우리팀.md') '우리팀.md 복사됨'
    Assert-True (Test-Path -LiteralPath (Join-Path $dir 'assets') -PathType Container) 'assets 폴더 생성'

    $doc = Get-Content -LiteralPath (Join-Path $dir '우리팀.md') -Raw -Encoding UTF8
    Assert-Contains $doc '조 번호: 03조' '우리팀.md 조번호 기입'
    Assert-Contains $doc '팀 이름: 지구지킴이' '우리팀.md 팀이름 기입'
    Assert-NotContains $doc '팀 이름: (아직 안 정함)' '팀이름 자리표시자 제거'
    Assert-NotContains $doc '조 번호: (아직 안 정함)' '조번호 자리표시자 제거'

    $html = Get-Content -LiteralPath (Join-Path $dir 'index.html') -Raw -Encoding UTF8
    Assert-Contains $html '03조 지구지킴이' '표지에 조번호·팀이름 반영'
    Assert-NotContains $html '00조 팀이름' '표지 자리표시자 제거'

    # --- 학생에게 쓰는 파일에는 BOM 이 없어야 한다 ---
    # (.ps1 소스는 BOM 이 필요하지만, 학생 파일은 반대다.
    #  HTML 앞의 BOM 은 렌더링 문제를 일으키고 bash 판과 바이트가 달라진다)
    foreach ($f in @('index.html', '우리팀.md')) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $dir $f))
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        Assert-Eq $hasBom $false ('BOM 없이 저장됨: ' + $f)
    }

    # --- 멱등: 두 번째 호출은 덮어쓰지 않는다 ---
    $marker = Join-Path $dir '학생작업.txt'
    '학생이 만든 내용' | Set-Content -LiteralPath $marker -Encoding utf8
    $dir2 = New-TeamFolder -Number 3 -Name '지구지킴이' -Parent $tmp -TemplateDir $Template
    Assert-Eq $dir2 $dir '같은 팀 재호출은 같은 경로 반환'
    Assert-FileExists $marker '학생 작업물이 보존됨'

    # --- 잘못된 인자 ---
    Assert-Eq (New-TeamFolder -Number 99 -Name '팀' -Parent $tmp -TemplateDir $Template) $null '잘못된 조번호는 null'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
