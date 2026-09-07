$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-shellfix.ps1"

# 앱이 .sh 도구를 실행할 수 있는지 지키는 시험.
#
# 실측 사고 (2026-09-02):
#   앱의 bash 도구는 윈도우에서 셸을 이렇게 고른다.
#     shell = (설정).shell ?? (COMSPEC ?? "cmd.exe")
#   기본이 cmd.exe 라서 camp-media.sh 를 실행하면 윈도우가
#   "이 .sh 파일을 어떤 앱으로 열까요?" 를 묻고 거기서 끝난다.
#   학생 63명이 그림을 하나도 못 만드는 상태였다.
#
#   설정에 shell 을 넣으면 해결된다. git bash 로 실제 생성까지 확인했다
#   (JPEG 1376x768 이 나왔다).

$tmp = Join-Path $env:TEMP ("campshell-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    # --- git bash 를 찾는가 ---
    $bash = Get-GitBashPath
    Assert-True ($null -ne $bash) 'git bash 를 찾는다'
    if ($null -ne $bash) {
        Assert-True (Test-Path -LiteralPath $bash -PathType Leaf) '찾은 bash.exe 가 실제로 있다'
        Assert-True ($bash -like '*bash.exe') '찾은 것이 bash.exe 다'
    }

    # --- 설정에 써 넣는가 ---
    $cfg = Join-Path $tmp 'opencode.json'
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($cfg, '{"model":"deepseek/deepseek-v4-flash"}', $enc)

    Assert-True (Set-CampShell -ConfigPath $cfg) '설정에 셸을 써 넣는다'
    $읽음 = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $읽음.shell $bash '써 넣은 셸이 찾은 bash 와 같다'
    Assert-Eq $읽음.model 'deepseek/deepseek-v4-flash' '원래 있던 값이 그대로다'

    # --- BOM 이 붙으면 앱이 설정을 못 읽는다 ---
    $b = [System.IO.File]::ReadAllBytes($cfg)
    Assert-True (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) '설정 파일에 BOM 이 없다'

    # --- 여러 번 해도 안전한가 ---
    Assert-True (Set-CampShell -ConfigPath $cfg) '두 번째도 성공으로 본다'
    $읽음2 = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Eq $읽음2.shell $bash '두 번 해도 값이 같다'

    # --- 깨진 설정은 건드리지 않는가 ---
    $깨진 = Join-Path $tmp 'broken.json'
    [System.IO.File]::WriteAllText($깨진, '{ 이건 JSON 이 아니다', $enc)
    Assert-True (-not (Set-CampShell -ConfigPath $깨진)) '깨진 설정은 실패로 보고한다'
    Assert-Eq (Get-Content -LiteralPath $깨진 -Raw -Encoding UTF8) '{ 이건 JSON 이 아니다' '깨진 설정을 덮어쓰지 않는다'

    # --- 없는 파일 ---
    Assert-True (-not (Set-CampShell -ConfigPath (Join-Path $tmp '없는파일.json'))) '없는 설정은 실패로 보고한다'

    # --- 설치 과정에 연결됐는가 ---
    $orch = Get-Content -LiteralPath "$Repo\dist\scripts\orchestrator.ps1" -Raw -Encoding UTF8
    Assert-Contains $orch 'Set-CampShell' '설치 과정이 셸을 잡는다'
    $cmdfile = Get-Content -LiteralPath "$Repo\dist\설치하기.cmd" -Raw
    Assert-Contains $cmdfile 'lib-shellfix.ps1' '설치하기.cmd 가 lib-shellfix 를 불러온다'
    $gui = Get-Content -LiteralPath "$Repo\dist\scripts\gui-install.ps1" -Raw -Encoding UTF8
    Assert-Contains $gui 'lib-shellfix.ps1' '설치 창도 lib-shellfix 를 불러온다'
    $bd = Get-Content -LiteralPath "$Repo\scripts\build-dist.ps1" -Raw -Encoding UTF8
    Assert-Contains $bd 'lib-shellfix.ps1' '빌드가 lib-shellfix 를 필수로 본다'

    # --- 권한 요청이 학생에게 뜨지 않는가 ---
    # 실측: 앱이 받는 키는 read edit glob grep list bash task external_directory
    #       todowrite question webfetch websearch lsp doom_loop skill
    $preset = Get-Content -LiteralPath "$Repo\camp-preset\opencode.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    # 하나라도 ask 면 학생이 그 창에서 멈춘다. 전부 allow 여야 한다.
    $묻지않을것 = @('read','edit','glob','grep','list','bash','task',
                    'external_directory','todowrite','question','lsp','doom_loop','skill',
                    'websearch','webfetch')
    foreach ($k in $묻지않을것) {
        Assert-Eq $preset.permission.$k 'allow' ('권한 ' + $k + ' 이 allow 다 (물어보면 학생이 멈춘다)')
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Summary) { exit 0 } else { exit 1 }
