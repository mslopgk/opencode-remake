# 설치가 실제로 됐는지 확정한다.
# 핵심: 프리셋 로드를 opencode 서버 API 로 "세어서" 확인한다 (실측 검증됨).

$script:ExpectedAgents = 4
$script:ExpectedCommands = 11
$script:AgentNames = @('도우미', '아이디어', '디자이너', '미디어')
$script:CommandNames = @('시작','아이디어','포스터','영상','슬라이드추가','보여줘','발표연습','제출','도와줘','합쳐줘','올리기')

function Get-FakeMode { return $env:CAMP_SELFCHECK_FAKE }

# 인터넷 없이 설치한 판인지 본다.
#
# 오프라인 판은 설치할 때 표를 남긴다. 그 판에서는 인터넷이 필요한 두 항목을
# 빨간불로 띄우면 안 된다. 학생은 잘못한 게 없는데 실패로 보이기 때문이다.
# 아주 오래된 윈도우인지 본다.
#
# 왜 필요한가 (실측, 2026-09-05 현장, Windows 10 1703):
#   opencode CLI 는 ClosePseudoConsole 이라는 윈도우 기능을 쓴다.
#   그건 1809 에서 처음 생겼다. 1703 에서 그 exe 를 실행하면 윈도우가
#   "프로시저 시작 지점을 찾을 수 없습니다" 라는 영어투 오류 창을 띄운다.
#   학생 화면에 그 창이 뜨면 그걸로 끝이다.
#   그래서 옛 윈도우에서는 CLI 를 쓰는 항목을 아예 부르지 않는다.
function Test-CampOldWindows {
    if ($env:CAMP_LEGACY -eq '1') { return $true }
    $방 = Join-Path $env:USERPROFILE '창의디자인캠프'
    if (Test-Path -LiteralPath (Join-Path $방 '옛윈도우.txt') -PathType Leaf) { return $true }
    # 표가 없어도 윈도우 자체가 옛것이면 같은 사고가 난다. 직접 본다.
    $build = 0
    try { $build = [int][Environment]::OSVersion.Version.Build } catch { $build = 0 }
    return ($build -gt 0 -and $build -lt 17763)
}

function Test-CampOffline {
    if ($env:CAMP_OFFLINE -eq '1') { return $true }
    $방 = Join-Path $env:USERPROFILE '창의디자인캠프'
    return (Test-Path -LiteralPath (Join-Path $방 '오프라인.txt') -PathType Leaf)
}


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
    if ($fake -eq 'ok')      { return @{ Ok = $true;  Agents = 4; Commands = 11 } }
    if ($fake -eq 'partial') { return @{ Ok = $false; Agents = 3; Commands = 11 } }
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

# 캠프 앱이 진짜 깔렸는지, .sh 도구를 돌릴 셸이 잡혔는지 본다.
#
# 왜 필요한가 (감사에서 나옴):
#   설치 계획은 "번들에 있는 파일" 만 넣는다. 백신이 앱 설치 파일을
#   격리하면 그 단계가 조용히 빠지는데, 점검은 앱 설치 여부를 한 번도
#   안 봤다. 그래서 "준비 끝!" 초록불이 뜨고, 캠프 당일 아침에야
#   앱이 없다는 걸 안다. 가장 늦게 발견되는 최악의 실패다.
#
#   셸도 마찬가지다. 못 잡으면 그림·영상·합치기·올리기가 전부
#   "이 .sh 파일을 어떤 앱으로 열까요?" 창에서 끝난다.
function Test-CampApp {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return @{ Ok = $true; Where = '(연습)' } }
    if ($fake -eq 'fail') { return @{ Ok = $false; Where = '앱이 없어요' } }

    $exe = Join-Path $env:LOCALAPPDATA 'Programs'
    $exe = Join-Path $exe '@opencode-aidesktop'
    $exe = Join-Path $exe 'OpenCode.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        return @{ Ok = $false; Where = '앱이 안 깔렸어요' }
    }

    $cfg = Join-Path $env:USERPROFILE '.config'
    $cfg = Join-Path $cfg 'opencode'
    $cfg = Join-Path $cfg 'opencode.json'
    $셸 = $null
    try { $셸 = (Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).shell } catch { }
    if ([string]::IsNullOrWhiteSpace($셸) -or -not (Test-Path -LiteralPath $셸 -PathType Leaf)) {
        return @{ Ok = $false; Where = '만들기 도구를 돌릴 준비가 덜 됐어요' }
    }
    return @{ Ok = $true; Where = '' }
}

# 진짜 파이썬이 있는지 본다.
#
# 윈도우는 파이썬이 없어도 python.exe / python3.exe 를 WindowsApps 에
# 심어 둔다. 스토어를 열어 주는 껍데기다. 이름만 보면 반드시 속는다.
# 그래서 (1) WindowsApps 경로는 버리고 (2) 실제로 실행해 본다.
function Test-RealPython {
    foreach ($n in @('python.exe', 'py.exe')) {
        foreach ($c in @(Get-Command $n -CommandType Application -ErrorAction SilentlyContinue)) {
            $src = ''
            try { $src = [string]$c.Source } catch { }
            if ($src -eq '') { continue }
            if ($src -like '*\WindowsApps\*') { continue }
            try {
                $global:LASTEXITCODE = 1
                $null = & $src '-c' 'pass' 2>$null
                if ($LASTEXITCODE -eq 0) { return $true }
            } catch { }
        }
    }
    return $false
}

# 그림·영상 만들기가 연결되는지 본다.
#
# 그림을 실제로 만들지 않는다. 한 장 $0.0336 이라 60명이 점검만 해도 $2 다.
# 대신 모델 목록 조회로 열쇠와 연결을 확인한다 — 이건 공짜다.
function Get-CampMediaKey([string]$Name) {
    $keyFile = Join-Path $env:USERPROFILE '.config\camp\media-keys.env'
    if (-not (Test-Path -LiteralPath $keyFile -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $keyFile -Encoding UTF8)) {
        if ($line.Trim() -match ('^\s*' + $Name + '\s*=\s*(.+)$')) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Test-MediaKeys {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return @{ Ok = $true; Where = '(연습)' } }
    if ($fake -eq 'fail') { return @{ Ok = $false; Where = '' } }

    $keyFile = Join-Path $env:USERPROFILE '.config\camp\media-keys.env'
    if (-not (Test-Path -LiteralPath $keyFile -PathType Leaf)) {
        return @{ Ok = $false; Where = '열쇠 파일이 없어요' }
    }
    $key = Get-CampMediaKey 'GEMINI_API_KEY'
    if (-not $key) { return @{ Ok = $false; Where = '열쇠가 비어 있어요' } }

    # 열쇠가 멀쩡해도 파이썬이 없으면 그림은 한 장도 안 나온다.
    # media-gen.py 를 돌리는 게 파이썬이기 때문이다.
    #
    # 이걸 안 보다가 사고가 났다 (student 계정, 2026-09-01):
    #   윈도우가 미리 심어 둔 껍데기 python.exe 때문에 인스톨러가
    #   파이썬을 건너뛰었는데, 점검은 초록불이었다.
    #   학생은 그림을 만들려는 순간에야 알게 된다.
    if (-not (Test-RealPython)) {
        return @{ Ok = $false; Where = '파이썬이 없어요' }
    }

    try {
        # 모델 목록 조회는 돈이 안 든다. 열쇠가 틀리면 400/403 이 온다.
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add('x-goog-api-key', $key)
        $raw = $wc.DownloadString('https://generativelanguage.googleapis.com/v1beta/models')
        return @{ Ok = ($raw -match '"models"'); Where = '' }
    }
    catch [System.Net.WebException] {
        $r = $_.Exception.Response
        if ($null -eq $r) { return @{ Ok = $false; Where = '인터넷이 안 돼요' } }
        $code = [int]$r.StatusCode
        $r.Close()
        if ($code -eq 400 -or $code -eq 401 -or $code -eq 403) {
            return @{ Ok = $false; Where = '열쇠가 맞지 않아요' }
        }
        return @{ Ok = $false; Where = '연결에 문제가 있어요' }
    }
    catch { return @{ Ok = $false; Where = '인터넷이나 열쇠에 문제가 있어요' } }
}

# 에이전트가 실행하는 도구가 실제로 있는지 확인한다.
#
# 이 점검이 없어서 "인스톨러가 도구를 아예 배포하지 않는다" 는 사실을
# 실기기 E2E 가 통과한 뒤에야 발견했다. 초록불이 4개여도 학생은
# /포스터 를 쓸 수 없는 상태였다.
function Test-CampTools {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return @{ Ok = $true; Missing = @() } }
    if ($fake -eq 'fail') { return @{ Ok = $false; Missing = @('camp-media.sh') } }

    $dir = Join-Path $env:LOCALAPPDATA 'Programs\camp-tools'
    $need = @('camp-media.sh', 'merge-slides.sh', 'merge-slides.py', 'camp-publish.sh', 'media-gen.py', 'camp-usage.sh')
    $missing = @()
    foreach ($n in $need) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $n) -PathType Leaf)) { $missing += $n }
    }
    return @{ Ok = ($missing.Count -eq 0); Missing = $missing }
}

# 발표자료를 인터넷에 올리는 도구가 깔렸는지 본다.
# 없으면 /올리기 가 캠프 당일에 실패한다 — 만들기 도구를 빠뜨려서
# 겪었던 것과 같은 종류의 사고다.
function Test-GithubCli {
    $fake = Get-FakeMode
    if ($fake -eq 'ok' -or $fake -eq 'partial') { return $true }
    if ($fake -eq 'fail') { return $false }

    $exe = Join-Path $env:LOCALAPPDATA 'Programs\gh-cli\bin\gh.exe'
    if (Test-Path -LiteralPath $exe -PathType Leaf) { return $true }
    return ($null -ne (Get-Command 'gh.exe' -CommandType Application -ErrorAction SilentlyContinue))
}

function Invoke-SelfCheck {
    Write-Step '설치가 잘 됐는지 확인할게요. 조금만 기다려 주세요.'
    $fails = @()

    # 1번은 "깔렸는지" 를 통째로 본다. 항목 수를 6개로 유지하는 이유는
    # 학생이 보는 영상이 "여섯 개 초록불" 이라고 말하기 때문이다.
    # 여기에 캠프 앱과 셸까지 넣어야, 앱이 없는데 초록불이 뜨는 일이 없다.
    $옛윈도우 = Test-CampOldWindows

    Write-Step '1/6 도구가 깔렸는지 확인 중'
    $앱 = Test-CampApp
    if ($옛윈도우) {
        # CLI 를 부르면 윈도우가 오류 창을 띄운다. 파일이 있는지만 본다.
        if ($앱.Ok) { Write-Ok '도구가 깔렸어요' }
        else { Write-Fail ('도구가 제대로 안 깔렸어요 — ' + $앱.Where); $fails += '도구' }
    }
    elseif (-not (Test-OpencodeVersion -Expected '1.18.20')) {
        Write-Fail '도구가 제대로 안 깔렸어요'; $fails += '도구'
    }
    elseif (-not $앱.Ok) {
        Write-Fail ('도구가 제대로 안 깔렸어요 — ' + $앱.Where); $fails += '도구'
    }
    else { Write-Ok '도구가 깔렸어요' }

    Write-Step '2/6 캠프 설정이 들어갔는지 확인 중'
    if ($옛윈도우) {
        # 이 확인도 CLI 로 서버를 띄운다. 옛 윈도우에서는 파일만 센다.
        $설정방 = Join-Path $env:USERPROFILE '.config\opencode'
        $도우미수 = @(Get-ChildItem -LiteralPath (Join-Path $설정방 'agent') -File -ErrorAction SilentlyContinue).Count
        $명령수 = @(Get-ChildItem -LiteralPath (Join-Path $설정방 'command') -File -ErrorAction SilentlyContinue).Count
        $p = @{ Ok = ($도우미수 -ge 4 -and $명령수 -ge 11); Agents = $도우미수; Commands = $명령수 }
    }
    else { $p = Test-PresetLoaded -Port 4399 }
    if ($p.Ok) { Write-Ok '캠프 설정이 들어갔어요' }
    else {
        Write-Fail ('캠프 설정이 덜 들어갔어요 (도우미 ' + $p.Agents + '/4, 명령 ' + $p.Commands + '/11)')
        $fails += '설정'
    }

    Write-Step '3/6 만들기 도구가 있는지 확인 중'
    $t = Test-CampTools
    if ($t.Ok) { Write-Ok '만들기 도구가 있어요' }
    else {
        Write-Fail ('만들기 도구가 없어요 (' + ($t.Missing -join ', ') + ')')
        $fails += '도구파일'
    }

    $오프라인 = Test-CampOffline

    # 오프라인 판은 먼저 해 보고, 안 되면 빨간불 대신 "나중에" 로 넘긴다.
    # 인터넷이 있으면 그대로 초록불이 되고, 없으면 학생을 겁주지 않는다.
    Write-Step '4/6 AI 도우미가 연결되는지 확인 중'
    if ($옛윈도우) {
        Write-Note '이 윈도우에서는 여기서 확인할 수 없어요. 캠프 시작을 눌러 직접 해 보세요.'
    }
    elseif (Test-DeepSeek) { Write-Ok 'AI 도우미가 연결됐어요' }
    elseif ($오프라인) { Write-Note 'AI 도우미는 인터넷을 연결한 뒤에 확인해요 (지금은 건너뜁니다)' }
    else { Write-Fail 'AI 도우미가 연결되지 않았어요'; $fails += 'AI' }

    Write-Step '5/6 그림 만들기가 연결되는지 확인 중'
    $h = Test-MediaKeys
    # 인터넷과 상관없는 실패는 오프라인 판에서도 봐주면 안 된다.
    # 특히 "파이썬이 없어요" 는 껍데기 파이썬 사고 때문에 일부러 넣은 검사인데,
    # 오프라인 면제가 그걸 통째로 삼키면 그림이 한 장도 안 나오는데 초록불이 뜬다.
    $로컬실패 = @('열쇠 파일이 없어요', '열쇠가 비어 있어요', '파이썬이 없어요')
    if ($h.Ok) { Write-Ok '그림 만들기가 연결됐어요' }
    elseif ($로컬실패 -contains $h.Where) {
        Write-Fail ('그림 만들기가 연결되지 않았어요 — ' + $h.Where); $fails += '그림'
    }
    elseif ($오프라인) { Write-Note '그림 만들기도 인터넷을 연결한 뒤에 확인해요 (지금은 건너뜁니다)' }
    else {
        if ($h.Where) { Write-Fail ('그림 만들기가 연결되지 않았어요 — ' + $h.Where) }
        else { Write-Fail '그림 만들기가 연결되지 않았어요' }
        $fails += '그림'
    }

    Write-Step '6/6 인터넷에 올리는 도구가 있는지 확인 중'
    if (Test-GithubCli) { Write-Ok '인터넷에 올리는 도구가 있어요' }
    else { Write-Fail '인터넷에 올리는 도구가 없어요'; $fails += '올리기' }

    Write-Host ''
    if ($fails.Count -eq 0) {
        Write-Ok '준비 끝! 이제 캠프시작을 눌러서 시작하면 돼요.'
        if ($옛윈도우) {
            Write-Note '(아주 오래된 윈도우예요. 캠프 시작을 눌러 앱이 열리는지 꼭 확인해 주세요)'
            Write-Note '앱이 안 열리면 그 노트북으로는 어렵습니다. 캠프에서 다른 노트북을 빌려 드려요.'
        }
        if ($오프라인) {
            Write-Note '(인터넷 없이 설치한 판이에요. 캠프에서 인터넷을 연결하면 그대로 쓸 수 있어요)'
        }
        return 0
    }

    Write-Fail ('안 된 것: ' + ($fails -join ', '))
    Write-Note '아래를 확인해 보세요.'
    # 집에서 혼자 설치하는 상황이다. 물어볼 사람이 없다.
    # 그래서 스스로 해 볼 수 있는 것만 알려 주고, 안 되면 그만하게 한다.
    # 별도 문의 창구를 두지 않는다 — 캠프 당일에 처리한다.
    Write-Note ''
    Write-Note '[1] 인터넷이 연결됐는지 확인해 주세요.'
    Write-Note '[2] 바탕화면의 "창의디자인캠프 설치" 를 한 번 더 실행해 주세요.'
    Write-Note '    (이미 깔린 것은 건너뛰므로 빠르게 끝납니다)'
    Write-Note '[3] 그 뒤에 "점검" 을 다시 실행해 주세요.'
    Write-Note ''
    Write-Note '두 번 해도 안 되면 여기서 그만하세요.'
    Write-Note '캠프 첫날 아침에 5분이면 고쳐 드립니다. 그냥 오시면 됩니다.'
    Write-Note ('(기록 파일은 ' + (Join-Path $env:USERPROFILE '창의디자인캠프') + ' 에 있습니다)')
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
