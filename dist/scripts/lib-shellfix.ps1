# 앱이 .sh 도구를 실행할 수 있게 셸을 잡아 준다.
#
# 왜 필요한가 (실측, 2026-09-02):
#   앱의 bash 도구는 윈도우에서 이렇게 셸을 고른다.
#
#     defaultShell = () => win32 ? (COMSPEC ?? "cmd.exe") : "/bin/sh"
#     shell = (설정).shell ?? defaultShell()
#
#   그래서 기본값이 cmd.exe 다. cmd.exe 에서 camp-media.sh 를 실행하면
#   윈도우가 "이 .sh 파일을 어떤 앱으로 열까요?" 를 묻는다.
#   학생은 거기서 멈춘다. 그림도 영상도 하나도 안 만들어진다.
#
#   설정에 shell 을 넣으면 그걸 쓴다. Git 을 깔면 같이 오는
#   bash.exe 를 넣어 준다. (Git 은 우리 인스톨러가 이미 설치한다)
#
# 왜 프리셋에 미리 못 박지 못하나:
#   Git 이 어디 깔릴지 노트북마다 다르다.
#     관리자로 깔면  C:\Program Files\Git\bin\bash.exe
#     아니면         %LOCALAPPDATA%\Programs\Git\bin\bash.exe
#   그래서 설치할 때 찾아서 넣는다.

function Get-GitBashPath {
    # 1) git.exe 가 있는 곳에서 거슬러 올라간다 (앱이 쓰는 방법과 같다)
    $git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue)
    foreach ($g in $git) {
        try {
            $bin = Split-Path -Parent $g.Source          # ...\Git\cmd  또는 ...\Git\bin
            $루트 = Split-Path -Parent $bin              # ...\Git
            # GitHub Desktop 이 품고 있는 git 은 usr 아래에 bash 를 둔다.
            # bin 만 보면 못 찾고, 그러면 셸을 못 잡아 .sh 도구가 전부 죽는다.
            foreach ($안 in @('bin', 'usr')) {
                $후보 = Join-Path $루트 $안
                if ($안 -eq 'usr') { $후보 = Join-Path $후보 'bin' }
                $후보 = Join-Path $후보 'bash.exe'
                if (Test-Path -LiteralPath $후보 -PathType Leaf) { return $후보 }
            }
        }
        catch { }
    }

    # 2) 흔히 깔리는 자리
    $자리 = @()
    $p = Join-Path $env:LOCALAPPDATA 'Programs'; $p = Join-Path $p 'Git'
    $p = Join-Path $p 'bin'; $자리 += (Join-Path $p 'bash.exe')
    foreach ($기본 in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($기본)) { continue }
        $p = Join-Path $기본 'Git'; $p = Join-Path $p 'bin'
        $자리 += (Join-Path $p 'bash.exe')
    }
    foreach ($후보 in $자리) {
        if (Test-Path -LiteralPath $후보 -PathType Leaf) { return $후보 }
    }
    return $null
}

# opencode.json 에 shell 을 써 넣는다. 이미 맞게 들어 있으면 그대로 둔다.
# 성공/이미맞음이면 $true.
function Set-CampShell {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $false }
    $bash = Get-GitBashPath
    if ($null -eq $bash) { return $false }

    try {
        $원본 = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
        $설정 = $원본 | ConvertFrom-Json
    }
    catch { return $false }        # 깨진 설정은 건드리지 않는다

    if ($설정.PSObject.Properties.Name -contains 'shell' -and $설정.shell -eq $bash) {
        return $true
    }
    $설정 | Add-Member -NotePropertyName 'shell' -NotePropertyValue $bash -Force

    try {
        # BOM 을 붙이면 앱이 JSON 을 못 읽는다. lib-appstate 의 사고와 같은 종류다.
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($ConfigPath, ($설정 | ConvertTo-Json -Depth 20), $enc)
        return $true
    }
    catch { return $false }
}
