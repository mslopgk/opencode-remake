# 설치가 실제로 됐는지 확정한다.
# 핵심: 프리셋 로드를 opencode 서버 API 로 "세어서" 확인한다 (실측 검증됨).

$script:ExpectedAgents = 4
$script:ExpectedCommands = 10
$script:AgentNames = @('도우미', '아이디어', '디자이너', '미디어')
$script:CommandNames = @('시작','아이디어','포스터','음악','영상','슬라이드추가','보여줘','발표연습','제출','도와줘')

function Get-FakeMode { return $env:CAMP_SELFCHECK_FAKE }

# Windows PowerShell 5.1 의 Invoke-RestMethod 는 charset 이 없는 응답을
# ISO-8859-1 로 디코딩한다. opencode 서버는 Content-Type: application/json 을
# charset 없이 보내므로 한국어 에이전트·명령 이름이 통째로 깨진다
# (도우미 -> 깨진 문자열). 실측으로 확인했고, 그래서 UTF-8 로 직접 디코딩한다.
function Get-JsonUtf8([string]$Uri, [int]$TimeoutSec) {
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $json = $wc.DownloadString($Uri)
        return ($json | ConvertFrom-Json)
    }
    finally { $wc.Dispose() }
}

# opencode 실행파일을 찾는다.
#
# 실측으로 확인한 함정: PATH 의 `opencode` 는 npm 셰임(opencode.ps1, ExternalScript)
# 으로 해석되고, Start-Process 는 .ps1 을 프로세스로 실행할 수 없어 서버가 뜨지 않는다.
# 또 데스크탑 앱(@opencode-aidesktop)에는 CLI 바이너리가 들어 있지 않다
# (OpenCode.exe 는 Electron 껍데기).
# 그래서 배포판은 standalone CLI(opencode-windows-x64.zip)를 따로 설치하고,
# 여기서 "진짜 실행파일" 경로를 직접 찾는다.
function Get-OpencodeExe {
    if ($env:CAMP_OPENCODE_EXE -and (Test-Path -LiteralPath $env:CAMP_OPENCODE_EXE -PathType Leaf)) {
        return $env:CAMP_OPENCODE_EXE
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\opencode-cli\opencode.exe'),
        (Join-Path $env:APPDATA 'npm\node_modules\opencode-ai\bin\opencode.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    $onPath = Get-Command 'opencode.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $onPath) { return $onPath.Source }
    return $null
}

function Test-OpencodeVersion([string]$Expected) {
    $fake = Get-FakeMode
    if ($fake) { return ($fake -eq 'ok' -or $fake -eq 'partial') }
    $exe = Get-OpencodeExe
    if ($null -eq $exe) { return $false }
    $out = & $exe --version
    if ($LASTEXITCODE -ne 0) { return $false }
    return (([string]$out).Trim() -eq $Expected)
}

function Test-PresetLoaded([int]$Port) {
    $fake = Get-FakeMode
    if ($fake -eq 'ok')      { return @{ Ok = $true;  Agents = 4; Commands = 10 } }
    if ($fake -eq 'partial') { return @{ Ok = $false; Agents = 3; Commands = 10 } }
    if ($fake -eq 'fail')    { return @{ Ok = $false; Agents = 0; Commands = 0 } }

    $exe = Get-OpencodeExe
    if ($null -eq $exe) { return @{ Ok = $false; Agents = 0; Commands = 0 } }
    $proc = Start-Process -FilePath $exe `
        -ArgumentList @('serve', '--port', $Port, '--hostname', '127.0.0.1') `
        -PassThru -WindowStyle Hidden
    try {
        $base = "http://127.0.0.1:$Port"
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 700
            try {
                Get-JsonUtf8 -Uri ($base + '/agent') -TimeoutSec 3 | Out-Null
                $ready = $true
                break
            } catch { }
        }
        if (-not $ready) { return @{ Ok = $false; Agents = 0; Commands = 0 } }

        $agents = Get-JsonUtf8 -Uri ($base + '/agent') -TimeoutSec 10
        $commands = Get-JsonUtf8 -Uri ($base + '/command') -TimeoutSec 30

        $agentNames = @()
        foreach ($a in @($agents)) { if ($a.name) { $agentNames += [string]$a.name } }
        $commandNames = @()
        foreach ($c in @($commands)) { if ($c.name) { $commandNames += [string]$c.name } }

        $na = 0
        foreach ($n in $script:AgentNames) { if ($agentNames -contains $n) { $na++ } }
        $nc = 0
        foreach ($n in $script:CommandNames) { if ($commandNames -contains $n) { $nc++ } }

        $ok = ($na -eq $script:ExpectedAgents -and $nc -eq $script:ExpectedCommands)
        return @{ Ok = $ok; Agents = $na; Commands = $nc }
    }
    finally {
        if ($null -ne $proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-DeepSeek {
    $fake = Get-FakeMode
    if ($fake) { return ($fake -eq 'ok' -or $fake -eq 'partial') }
    $exe = Get-OpencodeExe
    if ($null -eq $exe) { return $false }
    # 실측 함정: 도우미 에이전트가 없으면 opencode 가 기본 에이전트로 폴백해
    # 한국어로 답해버린다. 그러면 프리셋이 없는데도 이 점검이 통과한다.
    # 폴백 경고는 stderr 로 나가므로 파일로 따로 받아서 확인한다.
    # (네이티브 exe 에 2>&1 을 붙이면 5.1 에서 NativeCommandError 가 되므로 쓰지 않는다)
    $tmpOut = Join-Path $env:TEMP ('camp-ds-out-' + [guid]::NewGuid().ToString('N') + '.txt')
    $tmpErr = Join-Path $env:TEMP ('camp-ds-err-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process -FilePath $exe `
            -ArgumentList @('run', '안녕하세요', '--agent', '도우미') `
            -PassThru -Wait -WindowStyle Hidden `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
        if ($p.ExitCode -ne 0) { return $false }

        $errText = ''
        if (Test-Path -LiteralPath $tmpErr -PathType Leaf) {
            $errText = Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8
        }
        if ($errText -and $errText -match 'Falling back to default agent') { return $false }

        $text = ''
        if (Test-Path -LiteralPath $tmpOut -PathType Leaf) {
            $text = Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8
        }
        # 한국어 응답이 왔는지 (한글 음절이 하나라도 있으면 통과)
        return ($text -match '[가-힣]')
    }
    finally {
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

function Test-Higgsfield {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return @{ Ok = $true; Credits = 999.0 } }
    if ($fake -eq 'fail') { return @{ Ok = $false; Credits = 0.0 } }

    $cmd = Get-Command higgsfield -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return @{ Ok = $false; Credits = 0.0 } }
    $out = & higgsfield account status
    if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Credits = 0.0 } }
    $text = [string]::Join(' ', @($out))
    $credits = 0.0
    $m = [regex]::Match($text, '([0-9]+(\.[0-9]+)?)\s*credits')
    if ($m.Success) { $credits = [double]$m.Groups[1].Value }
    return @{ Ok = ($text -match 'credits'); Credits = $credits }
}

function Invoke-SelfCheck {
    Write-Step '설치가 잘 됐는지 확인할게요. 조금만 기다려 주세요.'
    $fails = @()

    Write-Step '1/4 도구가 깔렸는지 확인 중'
    if (Test-OpencodeVersion -Expected '1.18.20') { Write-Ok '도구가 깔렸어요' }
    else { Write-Fail '도구가 제대로 안 깔렸어요'; $fails += '도구' }

    Write-Step '2/4 캠프 설정이 들어갔는지 확인 중'
    $p = Test-PresetLoaded -Port 4399
    if ($p.Ok) { Write-Ok '캠프 설정이 들어갔어요' }
    else {
        Write-Fail ('캠프 설정이 덜 들어갔어요 (도우미 ' + $p.Agents + '/4, 명령 ' + $p.Commands + '/10)')
        $fails += '설정'
    }

    Write-Step '3/4 AI 도우미가 연결되는지 확인 중'
    if (Test-DeepSeek) { Write-Ok 'AI 도우미가 연결됐어요' }
    else { Write-Fail 'AI 도우미가 연결되지 않았어요'; $fails += 'AI' }

    Write-Step '4/4 그림 만들기가 연결되는지 확인 중'
    $h = Test-Higgsfield
    if ($h.Ok) {
        Write-Ok ('그림 만들기가 연결됐어요 (남은 양 ' + $h.Credits + ')')
        if ($h.Credits -lt 200) { Write-Note '남은 양이 적어요. 선생님께 알려 주세요.' }
    }
    else { Write-Fail '그림 만들기가 연결되지 않았어요'; $fails += '그림' }

    Write-Host ''
    if ($fails.Count -eq 0) {
        Write-Ok '준비 끝! 이제 캠프시작을 눌러서 시작하면 돼요.'
        return 0
    }

    Write-Fail ('안 된 것: ' + ($fails -join ', '))
    Write-Note '아래를 확인해 보세요.'
    if ($fails -contains '도구')  { Write-Note '- 설치하기를 다시 실행해 주세요.' }
    if ($fails -contains '설정')  { Write-Note '- 설치하기를 다시 실행하면 설정이 다시 들어갑니다.' }
    if ($fails -contains 'AI')    { Write-Note '- 인터넷이 연결됐는지 확인해 주세요.' }
    if ($fails -contains '그림')  { Write-Note '- 인터넷 확인 후에도 안 되면 선생님을 불러 주세요.' }
    Write-Note '그래도 안 되면 선생님께 기록 파일을 보여 주세요.'
    return 1
}

# 점검하기.cmd 가 부르는 함수. 한국어를 .cmd 에 두지 않기 위한 진입점이다
# (cmd.exe 는 UTF-8 배치 파일의 비ASCII 를 잘못 파싱한다 — 실측 확인).
function Start-CampCheck {
    $logPath = Join-Path $env:USERPROFILE '창의디자인캠프\점검기록.txt'
    Start-CampLog $logPath
    $rc = Invoke-SelfCheck
    Stop-CampLog
    return $rc
}
