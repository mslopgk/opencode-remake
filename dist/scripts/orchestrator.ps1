# 캠프 배포판 설치 오케스트레이터.
#
# 핵심 설계: 우리가 인스톨러를 만드는 게 아니라, 이미 코드 서명된 공식
# 인스톨러들을 조용히 순차 실행한다. 그래서 서명 인증서가 필요 없다.
# 모든 구성요소는 per-user 로 설치해 관리자 권한을 요구하지 않는다.

# 아주 오래된 윈도우를 쓰는 학생을 위한 판인지 본다.
#
# 왜 필요한가 (실측, 2026-09-05 현장): 1703(15063) 을 쓰는 학생이 한 명 있었다.
# 우리 검사는 1809 미만을 막는데, 그 기준은 per-user 글꼴 때문이다.
# 글꼴은 화면이 예뻐지는 것일 뿐 캠프에 꼭 필요하지 않다.
# 그래서 이 표가 있으면 기준을 1703 까지 낮추고 글꼴만 건너뛴다.
#
# 앱이 그 윈도우에서 진짜로 열리는지는 그 노트북에서 눌러 봐야 안다.
# 안 열리면 다른 노트북을 빌려주는 수밖에 없다. 그래서 이 판은 기본이 아니고,
# 그 학생에게만 따로 준다.
function Test-CampLegacy([string]$DistDir) {
    if ($env:CAMP_LEGACY -eq '1') { return $true }
    if ([string]::IsNullOrWhiteSpace($DistDir)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $DistDir 'legacy.flag') -PathType Leaf)
}

function Test-Prerequisites {
    param([string]$DistDir = '')
    $reasons = @()
    $옛판 = Test-CampLegacy -DistDir $DistDir

    # 함정: WMI 저장소가 망가진 오래된 가정용 PC 에서는 Get-CimInstance 가
    # 조용히 실패한다. 그러면 $os 가 $null 이고 [int]$null 은 0 이라
    # 멀쩡한 Windows 11 이 "Windows 10 이상 필요" 로 막힌다.
    # WMI 없이 읽을 수 있는 값을 먼저 쓰고, 그것도 실패하면 통과시킨다.
    $build = 0
    try { $build = [int][Environment]::OSVersion.Version.Build } catch { $build = 0 }
    if ($build -eq 0) {
        try { $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber } catch { $build = 0 }
    }
    # 1809(17763) 부터 per-user 글꼴과 이 앱이 돈다. 그보다 낮을 때만 막는다.
    # 옛 윈도우판은 1703(15063) 까지 받아 준다. 글꼴은 건너뛴다.
    $최소 = 17763
    if ($옛판) { $최소 = 15063 }
    if ($build -gt 0 -and $build -lt $최소) {
        if ($옛판) { $reasons += 'Windows 10 (1703) 이상이 필요해요.' }
        else { $reasons += 'Windows 10 (1809) 이상이 필요해요.' }
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        $reasons += ('64비트 Windows 가 필요해요. (지금: ' + $env:PROCESSOR_ARCHITECTURE + ')')
    }
    # 필요 공간: 번들 350MB + 설치되는 구성요소 약 1.5GB + 작업 공간.
    # 5GB 를 요구했더니 디스크가 거의 찬 노트북에서 이유 없이 막혔다(실측).
    # 테스트가 개발 PC 의 디스크 상태에 좌우되지 않게 넘길 수 있다.
    # 학생 노트북에서는 아무도 이 변수를 만들지 않으므로 항상 2.5GB 를 본다.
    $needGb = 2.5
    if ($env:CAMP_MIN_FREE_GB) {
        try { $needGb = [double]$env:CAMP_MIN_FREE_GB } catch { $needGb = 2.5 }
    }
    $drive = (Get-Item $env:USERPROFILE).PSDrive.Name
    $free = (Get-PSDrive $drive).Free
    if ($free -lt ($needGb * 1GB)) {
        # 반올림하면 4.97GB 가 "5GB" 로 보여서 "5GB 인데 왜 안 되냐" 가 된다.
        # 내림으로 표시해 메시지가 모순되지 않게 한다.
        $freeGb = [math]::Floor($free / 1GB * 10) / 10
        $reasons += ('빈 공간이 ' + $needGb + 'GB 이상 필요해요. (지금 ' + $freeGb + 'GB) 안 쓰는 파일을 지워 주세요.')
    }

    return @{ Ok = ($reasons.Count -eq 0); Reasons = $reasons }
}

# 화면 앞에 앉아 있는 사람이 누구인지 본다.
#
# 왜 필요한가: 설치는 관리자 권한으로 시작한다. 그런데 학생 계정이
# 관리자가 아니면 윈도우가 "다른 계정"의 비밀번호를 묻는다. 거기서
# 부모님 계정으로 올리면 설치가 부모님 폴더로 들어간다.
# 학생 바탕화면에는 아무것도 안 생기고, 아무도 이유를 모른다.
#
# WMI 는 느리거나 막혀 있을 수 있으므로 시간을 짧게 주고, 못 알아내면
# 그냥 넘어간다. 확인 못 하는 것 때문에 설치를 막지는 않는다.
function Get-CampScreenUser {
    try {
        # 같은 세션의 explorer 만 본다.
        #
        # 왜 (실측, 2026-09-05): 이 기계에서 사용자가 한 명인데 explorer.exe 가
        # 두 개였다. 빠른 사용자 전환을 쓰면 부모 계정의 explorer 가 남아 있다.
        # 그걸 먼저 집으면, 정상적으로 자기 계정으로 승격했는데도
        # "다른 계정으로 시작했어요" 로 막아 버린다.
        $내세션 = (Get-Process -Id $PID).SessionId
        $ex = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" `
                    -OperationTimeoutSec 5 -ErrorAction Stop |
                Where-Object { $_.SessionId -eq $내세션 })
        foreach ($p in $ex) {
            $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner `
                    -OperationTimeoutSec 5 -ErrorAction SilentlyContinue
            if ($null -ne $o -and $o.User) {
                # 학교 도메인 계정과 로컬 계정은 이름이 같을 수 있다. 함께 본다.
                if ($o.Domain) { return ([string]$o.Domain + '' + [string]$o.User) }
                return [string]$o.User
            }
        }
    }
    catch { }
    return $null
}

function Test-CampSameUser {
    $화면 = Get-CampScreenUser
    if ([string]::IsNullOrWhiteSpace($화면)) { return @{ Ok = $true; Screen = $null } }
    $나 = $env:USERDOMAIN + '' + $env:USERNAME
    if ($화면 -eq $나 -or $화면 -eq $env:USERNAME) { return @{ Ok = $true; Screen = $화면 } }
    return @{ Ok = $false; Screen = $화면 }
}

function Unblock-BundleFiles([string]$DistDir) {
    # USB·다운로드로 온 파일에는 차단 플래그가 붙는다.
    # 이걸 안 떼면 60대에서 전부 막힌다.
    Get-ChildItem -LiteralPath $DistDir -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
}

# 진짜 실행되는 프로그램인지 본다. 이름만 있는 "껍데기" 를 걸러낸다.
#
# 실측 사고 (student 계정, 2026-09-01):
#   윈도우는 파이썬이 없어도 python.exe / python3.exe 를
#   %LOCALAPPDATA%\Microsoft\WindowsApps 에 미리 심어 둔다.
#   이건 마이크로소프트 스토어를 열어 주는 껍데기(AppInstallerPythonRedirector.exe)다.
#   Get-Command 는 파일이 있으니 찾아냈고, 설치기록에는
#   "파이썬 은(는) 이미 있어요. 넘어갈게요" 가 찍혔다.
#   결과: 파이썬이 한 번도 안 깔렸고 그림·영상 만들기가 통째로 죽는다.
#   윈도우 노트북 전부가 이 껍데기를 갖고 있으므로 학생 63명 전원에게 터진다.
#
# 그래서 두 겹으로 막는다.
#   1) WindowsApps 경로에 있는 것은 무조건 껍데기로 본다
#   2) 실제로 한 번 실행해 본다 (껍데기는 0 이 아닌 값을 뱉는다)
function Test-RealExe([string[]]$Names, [string[]]$Probe) {
    foreach ($n in $Names) {
        $found = @(Get-Command $n -CommandType Application -ErrorAction SilentlyContinue)
        foreach ($c in $found) {
            $src = ''
            try { $src = [string]$c.Source } catch { }
            if ($src -eq '') { continue }
            if ($src -like '*\WindowsApps\*') { continue }
            try {
                # 이전 명령의 종료값이 남아 오판하지 않게 먼저 지운다.
                $global:LASTEXITCODE = 1
                $null = & $src @Probe 2>$null
                if ($LASTEXITCODE -eq 0) { return $true }
            } catch { }
        }
    }
    return $false
}

# 이미 설치돼 있으면 건너뛴다.
#
# 두 가지 이유로 필요하다:
#  1) 학생 노트북에 이미 Node 나 Git 이 있으면 다시 깔 이유가 없다 (설치 시간 단축)
#  2) 이미 쓰던 버전을 우리가 덮어써서 학생·개발자 환경을 망치지 않는다
function Test-ComponentInstalled([string]$Kind, [string]$File) {
    if ($env:CAMP_FORCE_INSTALL_ALL -eq '1') { return $false }

    if ($File -eq 'node-lts-x64.msi') {
        return (Test-RealExe -Names @('node.exe') -Probe @('--version'))
    }
    if ($File -eq 'python-3.12-amd64.exe') {
        # 파이썬은 반드시 Test-RealExe 로 봐야 한다. 위의 "껍데기" 주석 참고.
        return (Test-RealExe -Names @('python.exe', 'py.exe') -Probe @('-c', 'pass'))
    }
    if ($File -eq 'Git-64-bit.exe') {
        return (Test-RealExe -Names @('git.exe') -Probe @('--version'))
    }
    if ($Kind -eq 'font') {
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $key)) { return $false }
        $reg = Get-ItemProperty -Path $key
        # 실측 함정: Nerd Font 는 Cascadia 를 "CaskaydiaCove" 로 이름을 바꾼다.
        # Cascadia 만 찾으면 이미 설치된 것을 못 알아보고 재설치하다가
        # "파일이 사용 중" 오류가 난다.
        #
        # 등록만 보면 안 된다. 글꼴 파일을 지워도 등록은 남아서
        # "이미 있어요" 로 건너뛰고, 터미널 글자가 전부 두부(□)가 된다.
        # 그래서 등록이 가리키는 파일이 실제로 있는지까지 본다.
        $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        foreach ($n in $reg.PSObject.Properties.Name) {
            if ($n -notlike '*Caskaydia*' -and $n -notlike '*Cascadia*') { continue }
            $path = [string]$reg.$n
            if ($path -eq '') { continue }
            if (-not [System.IO.Path]::IsPathRooted($path)) {
                $path = Join-Path $fontDir $path
            }
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $true }
        }
        return $false
    }
    if ($File -eq 'opencode-desktop-win-x64.exe') {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop\OpenCode.exe'
        return (Test-Path -LiteralPath $exe -PathType Leaf)
    }
    if ($Kind -eq 'ghzip') {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\gh-cli\bin\gh.exe'
        return (Test-Path -LiteralPath $exe -PathType Leaf)
    }
    if ($Kind -eq 'clizip') {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\opencode-cli\opencode.exe'
        return (Test-Path -LiteralPath $exe -PathType Leaf)
    }
    return $false
}

# 설치 프로그램의 "성공" 은 0 하나가 아니다.
#
#   3010 / 1641 = 다 깔렸고 재부팅만 하면 된다 (실패 아님)
#
# 이걸 실패로 보면 1/7 단계에서 통째로 멈춰 뒤의 파이썬·Git·앱·설정이
# 하나도 안 깔린다. 학생은 "노드 설치에 실패했어요" 한 줄만 본다.
function Test-InstallExitOk([int]$Code) {
    return ($Code -eq 0 -or $Code -eq 3010 -or $Code -eq 1641)
}

function Get-InstallPlan([string]$BundleDir) {
    $candidates = @(
        @{ Name = '노드 (AI 도구가 쓰는 부품)'; File = 'node-lts-x64.msi';            Kind = 'msi';    Args = @('/qn', 'ALLUSERS=0') },
        @{ Name = '파이썬';                     File = 'python-3.12-amd64.exe';       Kind = 'exe';    Args = @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0') },
        @{ Name = 'Git';                        File = 'Git-64-bit.exe';              Kind = 'exe';    Args = @('/VERYSILENT', '/NORESTART', '/NOCANCEL') },
        @{ Name = '글꼴';                       File = 'CascadiaCode-NF.zip';         Kind = 'font';   Args = @() },
        @{ Name = '캠프 앱';                    File = 'opencode-desktop-win-x64.exe'; Kind = 'exe';   Args = @('/S') },
        @{ Name = '점검용 도구';                File = 'opencode-windows-x64.zip';    Kind = 'clizip'; Args = @() },
        @{ Name = '인터넷에 올리는 도구';       File = 'gh-windows-amd64.zip';        Kind = 'ghzip';  Args = @() }
    )

    $plan = @()
    foreach ($c in $candidates) {
        $path = Join-Path $BundleDir $c.File
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $c['Path'] = $path
            $c['AlreadyInstalled'] = (Test-ComponentInstalled -Kind $c.Kind -File $c.File)
            $plan += $c
        }
    }
    return $plan
}

function Expand-ZipTo([string]$ZipPath, [string]$Dest) {
    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Dest)
}

function Install-Font([string]$ZipPath) {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path -LiteralPath $fontDir)) {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    }
    $tmp = Join-Path $env:TEMP ('font-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-ZipTo -ZipPath $ZipPath -Dest $tmp
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Get-ChildItem -LiteralPath $tmp -Recurse -Include '*.ttf', '*.otf' -File | ForEach-Object {
            $dest = Join-Path $fontDir $_.Name
            # 이미 설치돼 쓰이는 중인 글꼴 파일은 덮어쓸 수 없다.
            # 그건 실패가 아니라 "이미 있음" 이므로 넘어간다.
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                Set-ItemProperty -Path $key -Name $_.BaseName -Value $dest
                return
            }
            try {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                Set-ItemProperty -Path $key -Name $_.BaseName -Value $dest
            }
            catch {
                # 한 글꼴이 실패해도 나머지는 계속 넣는다. 글꼴은 필수가 아니다
                # (학생은 GUI 를 쓰고, 글꼴은 터미널 글리프에만 영향).
            }
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Install-OpencodeCli([string]$ZipPath) {
    # 데스크탑 앱에는 CLI 바이너리가 없다(실측 확인). 자체 점검이 CLI 를
    # 필요로 하므로 standalone 을 따로 풀어 넣는다.
    $dest = Join-Path $env:LOCALAPPDATA 'Programs\opencode-cli'
    if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force $dest }
    $tmp = Join-Path $env:TEMP ('occli-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-ZipTo -ZipPath $ZipPath -Dest $tmp
        $exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'opencode.exe' -File | Select-Object -First 1
        if ($null -eq $exe) { return $false }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        # zip 안의 구조를 그대로 옮긴다 (실행에 필요한 파일이 함께 있을 수 있다)
        Copy-Item -Path (Join-Path $exe.Directory.FullName '*') -Destination $dest -Recurse -Force
        return (Test-Path -LiteralPath (Join-Path $dest 'opencode.exe') -PathType Leaf)
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Install-GithubCli([string]$ZipPath) {
    # 발표자료를 인터넷에 올릴 때 쓴다.
    # 관리자 권한을 피하려고 MSI 가 아니라 zip 을 쓴다. 학생 노트북에서
    # 관리자 암호를 물으면 거기서 설치가 멈춘다.
    $dest = Join-Path $env:LOCALAPPDATA 'Programs\gh-cli'
    if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force $dest }
    $tmp = Join-Path $env:TEMP ('ghcli-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-ZipTo -ZipPath $ZipPath -Dest $tmp
        $exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'gh.exe' -File | Select-Object -First 1
        if ($null -eq $exe) { return $false }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        # zip 안의 구조(bin\, share\)를 통째로 옮긴다
        $root = $exe.Directory.Parent
        if ($null -eq $root) { $root = $exe.Directory }
        Copy-Item -Path (Join-Path $root.FullName '*') -Destination $dest -Recurse -Force
        $ghExe = Join-Path $dest 'bin\gh.exe'
        if (-not (Test-Path -LiteralPath $ghExe -PathType Leaf)) { return $false }
        Add-CampUserPath (Join-Path $dest 'bin')
        return $true
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

# 방금 설치된 것을 이 프로세스가 알아보게 PATH 를 다시 읽는다.
#
# 왜 필요한가: 파이썬·Git 인스톨러는 레지스트리의 Path 만 고친다.
# 이미 돌고 있는 프로세스의 $env:PATH 는 옛 값 그대로다.
# 설치가 끝나자마자 자체 점검이 돌기 때문에, 이걸 안 하면
# 방금 깐 파이썬을 못 찾아 "그림 만들기가 연결되지 않았어요" 라고
# 거짓 빨간불이 뜬다. 학생은 멀쩡한 설치를 실패로 안다.
function Update-CampPath {
    $조각 = @()
    foreach ($k in @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
                     'HKCU:\Environment')) {
        try {
            $v = [string](Get-ItemProperty -Path $k -Name 'Path' -ErrorAction Stop).Path
            if ($v) { $조각 += @($v -split ';' | Where-Object { $_ -ne '' }) }
        } catch { }
    }
    # 지금 프로세스에만 넣어 둔 경로(Add-CampUserPath) 도 잃지 않게 합친다.
    $조각 += @($env:PATH -split ';' | Where-Object { $_ -ne '' })

    $본것 = @{}
    $결과 = @()
    foreach ($d in $조각) {
        # [char]92 는 역슬래시. 따옴표 안에 그냥 쓰면 이스케이프에 먹힌다.
        $키 = $d.TrimEnd([char]92).ToLowerInvariant()
        if ($본것.ContainsKey($키)) { continue }
        $본것[$키] = $true
        $결과 += $d
    }
    $env:PATH = ($결과 -join ';')
}

# 사용자 PATH 에 폴더 하나를 추가한다 (per-user, 관리자 권한 불필요).
# setx 는 값을 자르거나 확장해버릴 수 있으므로 레지스트리를 직접 쓴다.
function Add-CampUserPath([string]$Dir) {
    $key = 'HKCU:\Environment'
    $current = ''
    try {
        $current = [string](Get-ItemProperty -Path $key -Name 'Path' -ErrorAction Stop).Path
    } catch { $current = '' }

    $parts = @()
    if ($current) { $parts = @($current -split ';' | Where-Object { $_ -ne '' }) }
    if ($parts -notcontains $Dir) {
        $newPath = (@($parts) + @($Dir)) -join ';'
        Set-ItemProperty -Path $key -Name 'Path' -Value $newPath
    }

    # 이번 프로세스에서도 바로 쓰이도록 넣어준다 (앱은 다음 실행 때 상속)
    if (($env:PATH -split ';') -notcontains $Dir) {
        $env:PATH = $env:PATH + ';' + $Dir
    }
}

# 에이전트가 실행하는 도구를 설치하고 사용자 PATH 에 등록한다.
#
# 이게 없으면 /포스터·/음악·/영상·/합쳐줘 가 전부 실패한다.
# 개발 중에는 테스트가 PATH 를 직접 넣어줘서 문제가 안 보였다 — 실제로 겪은 함정.
function Install-CampTools([string]$DistDir) {
    $src = Join-Path $DistDir 'tools'
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { return $false }

    $dst = Join-Path $env:LOCALAPPDATA 'Programs\camp-tools'
    if (-not (Test-Path -LiteralPath $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Force

    Add-CampUserPath $dst

    return (Test-Path -LiteralPath (Join-Path $dst 'camp-media.sh') -PathType Leaf)
}

# 바탕화면에 바로가기를 만든다.
#
# 왜 필요한가: 설치 파일은 %LOCALAPPDATA% 안에 풀린다. 학생은 그 폴더를
# 찾아갈 수 없다. 문서와 강의 대본이 "바탕화면에 아이콘이 생깁니다" 라고
# 약속하므로 실제로 만들어야 한다.
#
# 실측 사고: ZIP 을 바탕화면에 풀던 방식에서 exe 자동해제 방식으로 바꿀 때
# 이 단계를 빼먹었다. 다른 사용자 계정에서 설치했더니 아이콘이 하나도
# 생기지 않았다. 녹화 중에 발견했다.
#
# OneDrive 를 쓰면 바탕화면이 옮겨져 있으므로 Windows 에 직접 물어본다.
# 캠프 앱의 자동 업데이트를 끈다.
#
# 왜 끄는가 (실측, 2026-09-02):
#   앱은 GitHub 에서 새 버전을 스스로 받아 온다(app-update.yml, channel: latest).
#   캠프 날 노트북 63대가 각자 126MB 를 받고 "재시작할까요?" 를 띄우면
#   수업이 멈춘다. 캠프 와이파이도 못 견딘다.
#   더 나쁜 것은 버전이 바뀌면서 설정 형식이 달라지는 경우다. 도우미가
#   조용히 안 뜨는데 아무도 이유를 모른다.
#
#   설정 자체는 앱 폴더 밖(~/.config/opencode 등)에 있어서 업데이트로
#   지워지지는 않는다. 문제는 "언제 무엇이 바뀔지 모른다" 는 것이다.
#   캠프가 끝날 때까지는 우리가 시험한 그 버전으로 고정한다.
#
# 어떻게: electron-updater 는 resources 폴더의 app-update.yml 이 없으면
#   업데이트 기능을 스스로 끈다. 파일을 지우지 않고 이름만 바꿔 둔다.
#   되돌리고 싶으면 이름만 되돌리면 된다.
function Disable-AppAutoUpdate {
    # 경로를 한 줄로 쓰면 역슬래시가 제어문자로 먹히는 사고가 난다.
    # 조각으로 나눠 이어 붙인다.
    $yml = Join-Path $env:LOCALAPPDATA 'Programs'
    $yml = Join-Path $yml '@opencode-aidesktop'
    $yml = Join-Path $yml 'resources'
    $yml = Join-Path $yml 'app-update.yml'
    $끈것 = $yml + '.캠프에서끔'
    if (-not (Test-Path -LiteralPath $yml -PathType Leaf)) {
        return (Test-Path -LiteralPath $끈것 -PathType Leaf)   # 이미 꺼져 있으면 성공
    }
    try {
        if (Test-Path -LiteralPath $끈것) { Remove-Item -LiteralPath $끈것 -Force }
        Rename-Item -LiteralPath $yml -NewName (Split-Path -Leaf $끈것) -Force
        return $true
    }
    catch { return $false }
}

function New-CampShortcuts([string]$DistDir) {
    $desktop = $null
    try { $desktop = [Environment]::GetFolderPath('Desktop') } catch { }
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
        $desktop = Join-Path $env:USERPROFILE 'Desktop'
    }
    if (-not (Test-Path -LiteralPath $desktop -PathType Container)) { return 0 }

    # 학생이 실제로 누르는 것들. 순서가 바탕화면 정렬에 영향을 준다.
    $targets = @(
        '캠프 시작.exe',
        '발표자료 보기.exe',
        '점검.exe',
        '창의디자인캠프 설치.exe',
        '깃허브 연결.exe'
    )

    $made = 0
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return 0 }

    foreach ($name in $targets) {
        $exe = Join-Path $DistDir $name
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $lnk = Join-Path $desktop ([System.IO.Path]::GetFileNameWithoutExtension($name) + '.lnk')
        try {
            $sc = $shell.CreateShortcut($lnk)
            $sc.TargetPath = $exe
            $sc.WorkingDirectory = $DistDir
            $sc.IconLocation = $exe + ',0'
            $sc.Save()
            $made++
        }
        catch { }
    }

    if ($null -ne $shell) {
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch { }
    }
    return $made
}

# 인터넷 없이 설치할 수 있게, 앱이 첫 실행 때 받아오는 것들을 미리 넣어 준다.
#
# 왜 필요한가 (실측, 2026-09-05 행사장):
#   앱은 처음 켤 때 인터넷에서 세 가지를 받아온다.
#     ~/.cache/opencode/models.json        4.5MB  (모델 목록)
#     ~/.cache/opencode/bin/rg.exe         4.2MB  (검색 도구)
#     ~/.config/opencode/node_modules     61MB    (플러그인 꾸러미)
#   합쳐서 한 사람당 70MB 다. 60명이면 4GB 를 바깥 회선으로 빨아들인다.
#   행사장 들어오는 회선이 100Mbps 라 그러면 회선이 죽는다.
#
#   그래서 오프라인 판에는 이걸 짐에 같이 넣고, 설치할 때 풀어 준다.
#   이미 있는 파일은 건드리지 않는다. 학생이 쓰던 것을 덮어쓰면 안 된다.
#
# 짐이 없으면(온라인 판) 아무 일도 하지 않는다. 그래서 두 판이 같은 코드를 쓴다.
function Restore-OfflineCache([string]$DistDir) {
    $짐 = Join-Path $DistDir 'offline'
    if (-not (Test-Path -LiteralPath $짐 -PathType Container)) { return $null }

    $넣을곳 = @(
        @{ Zip = 'opencode-cache.zip';  Dest = (Join-Path (Join-Path $env:USERPROFILE '.cache') 'opencode') },
        @{ Zip = 'opencode-config.zip'; Dest = (Join-Path (Join-Path $env:USERPROFILE '.config') 'opencode') }
    )

    $푼것 = 0
    foreach ($ㅎ in $넣을곳) {
        $zip = Join-Path $짐 $ㅎ.Zip
        if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { continue }
        if (-not (Test-Path -LiteralPath $ㅎ.Dest)) {
            New-Item -ItemType Directory -Path $ㅎ.Dest -Force | Out-Null
        }
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $a = [System.IO.Compression.ZipFile]::OpenRead($zip)
            try {
                $뿌리 = [System.IO.Path]::GetFullPath($ㅎ.Dest)
                foreach ($e in $a.Entries) {
                    if ([string]::IsNullOrEmpty($e.Name)) { continue }   # 폴더 항목
                    $갈곳 = [System.IO.Path]::GetFullPath((Join-Path $ㅎ.Dest $e.FullName))
                    # zip 안에 ..\ 가 들어 있어도 밖으로 못 나가게 막는다
                    if (-not $갈곳.StartsWith($뿌리, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    if (Test-Path -LiteralPath $갈곳 -PathType Leaf) { continue }   # 쓰던 것은 그대로 둔다
                    $부모 = Split-Path -Parent $갈곳
                    if (-not (Test-Path -LiteralPath $부모)) {
                        New-Item -ItemType Directory -Path $부모 -Force | Out-Null
                    }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $갈곳, $false)
                    $푼것++
                }
            }
            finally { $a.Dispose() }
        }
        catch { }      # 하나 실패해도 설치는 계속한다. 인터넷이 있으면 앱이 알아서 받는다.
    }

    # 진짜로 풀렸을 때만 오프라인 판이라고 표시한다.
    #
    # 왜 (감사에서 나옴): 백신이 zip 을 격리했거나 디스크가 찼으면 위 catch 가
    # 조용히 삼킨다. 그런데도 표를 남기면, 점검이 인터넷 항목 두 개를 봐줘서
    # 준비물이 하나도 없는 컴퓨터에 "준비 끝!" 초록불이 뜬다.
    $꾸러미 = Join-Path (Join-Path (Join-Path $env:USERPROFILE '.config') 'opencode') 'node_modules'
    $모델 = Join-Path (Join-Path (Join-Path $env:USERPROFILE '.cache') 'opencode') 'models.json'
    if (-not (Test-Path -LiteralPath $꾸러미 -PathType Container) -or
        -not (Test-Path -LiteralPath $모델 -PathType Leaf)) {
        Write-Fail '인터넷 없이 쓸 준비물을 넣지 못했어요. 백신이 막았을 수 있어요.'
        return $푼것
    }

    # 점검이 "인터넷 항목은 건너뛴다" 를 알 수 있게 표를 남긴다.
    try {
        $방 = Join-Path $env:USERPROFILE '창의디자인캠프'
        if (-not (Test-Path -LiteralPath $방)) { New-Item -ItemType Directory -Path $방 -Force | Out-Null }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $방 '오프라인.txt'),
            "인터넷 없이 설치한 판입니다.`r`n인터넷을 연결한 뒤 점검을 다시 하면 AI 연결까지 확인합니다.`r`n", $enc)
    }
    catch { }
    $env:CAMP_OFFLINE = '1'
    return $푼것
}

function Copy-PresetAndSecrets([string]$DistDir) {
    # 프리셋
    $presetSrc = Join-Path $DistDir 'preset'
    $presetDst = Join-Path $env:USERPROFILE '.config\opencode'
    if (Test-Path -LiteralPath $presetSrc -PathType Container) {
        $있음 = (Test-Path -LiteralPath $presetDst) -and
                (@(Get-ChildItem -LiteralPath $presetDst -Force)).Count -gt 0

        # 거기 있는 것이 우리가 깐 캠프 설정인지 본다.
        #
        # 왜 구분하는가 (실측, 2026-09-05):
        #   설치가 잘 안 되면 학생은 설치를 두 번 세 번 다시 누른다.
        #   그때마다 통째로 백업하면 node_modules 61MB 가 같이 복사돼 쌓인다.
        #   이 기계에서 다섯 번에 226MB 가 쌓였다. 학생 노트북은 공간이
        #   빠듯해서, 설치를 다시 할수록 "빈 공간이 부족해요" 로 끝난다.
        #
        #   우리가 깐 것이면 백업하지 않는다. 대신 프리셋 폴더만 지우고
        #   새로 넣는다. node_modules 는 그대로 두어 인터넷 없이도 바로 쓴다.
        $우리것 = $false
        if ($있음) {
            foreach ($표 in @('agent\도우미.md', 'command\합쳐줘.md')) {
                if (Test-Path -LiteralPath (Join-Path $presetDst $표) -PathType Leaf) {
                    $우리것 = $true; break
                }
            }
        }

        if ($있음 -and -not $우리것) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Move-Item -LiteralPath $presetDst -Destination ($presetDst + '.backup-' + $stamp)
            Write-Note '원래 쓰던 설정은 따로 보관했어요.'
        }
        elseif ($우리것) {
            # 옛 프리셋에만 있던 파일이 남지 않게, 우리가 넣는 것만 지운다.
            foreach ($ㅈ in @('agent', 'command', 'skills')) {
                $길 = Join-Path $presetDst $ㅈ
                if (Test-Path -LiteralPath $길) { Remove-Item -LiteralPath $길 -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        New-Item -ItemType Directory -Path $presetDst -Force | Out-Null
        Copy-Item -Path (Join-Path $presetSrc '*') -Destination $presetDst -Recurse -Force
    }

    # 키
    $sec = Join-Path $DistDir 'secrets'
    if (Test-Path -LiteralPath (Join-Path $sec 'auth.json') -PathType Leaf) {
        $dst = Join-Path $env:USERPROFILE '.local\share\opencode'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sec 'auth.json') -Destination $dst -Force
    }
    # Higgsfield 자격증명은 더 이상 심지 않는다.
    # 미디어를 Google Gemini API 직결로 옮겼으므로 쓰지 않고, 이 계정은
    # 폐기 명령이 없어서(로그인·로그아웃·토큰 조회만 있다) 60대에 뿌리면
    # 회수할 방법이 없다. 쓰지 않는 열쇠를 배포하지 않는다.

    # 그림·영상 만들기 열쇠 (Cloudflare / fal).
    # camp-media.sh 가 ~/.config/camp/media-keys.env 를 읽는다.
    $keys = Join-Path $sec 'media-keys.env'
    if (Test-Path -LiteralPath $keys -PathType Leaf) {
        $dst = Join-Path $env:USERPROFILE '.config\camp'
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Copy-Item -LiteralPath $keys -Destination $dst -Force
    }
}

function Invoke-Install {
    param(
        [Parameter(Mandatory=$true)][string]$DistDir,
        [switch]$DryRun,
        [switch]$SkipSelfCheck
    )

    if ($DryRun) { Write-Note '연습 모드입니다. 실제로 설치하지 않습니다.' }

    Write-Step '컴퓨터를 확인하고 있어요'
    $pre = Test-Prerequisites -DistDir $DistDir
    if (-not $pre.Ok) {
        foreach ($r in $pre.Reasons) { Write-Fail $r }
        return 1
    }
    Write-Ok '컴퓨터는 괜찮아요'

    # 옛 윈도우판이면 표를 남긴다. 점검이 나중에 따로 실행돼도 알아야 한다.
    if (Test-CampLegacy -DistDir $DistDir) {
        $env:CAMP_LEGACY = '1'
        try {
            $방 = Join-Path $env:USERPROFILE '창의디자인캠프'
            if (-not (Test-Path -LiteralPath $방)) { New-Item -ItemType Directory -Path $방 -Force | Out-Null }
            $enc = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText((Join-Path $방 '옛윈도우.txt'),
                "아주 오래된 윈도우에 맞춘 판입니다.`r`n점검용 도구는 이 윈도우에서 실행되지 않아 건너뜁니다.`r`n", $enc)
        }
        catch { }
    }

    # 관리자 권한을 다른 계정으로 올렸으면 여기서 멈춘다.
    # 그대로 두면 설치가 통째로 엉뚱한 사람의 폴더로 들어간다.
    $같은사람 = Test-CampSameUser
    if (-not $같은사람.Ok) {
        Write-Fail '설치를 이 컴퓨터의 다른 계정으로 시작했어요.'
        Write-Note ('지금 쓰는 사람: ' + $같은사람.Screen + ' / 설치를 맡은 계정: ' + $env:USERNAME)
        Write-Note '이대로 하면 바탕화면에 아이콘이 하나도 안 생겨요.'
        Write-Note ('먼저 ' + $같은사람.Screen + ' 계정을 관리자로 만든 뒤 다시 해 주세요.')
        Write-Note '(설정 > 계정 > 다른 사용자 에서 계정 유형을 관리자로 바꿉니다)'
        Write-Note '잘 안 되면 여기서 그만하세요. 캠프 첫날 아침에 고쳐 드립니다.'
        return 1
    }

    Write-Step '파일 차단을 풀고 있어요'
    if (-not $DryRun) { Unblock-BundleFiles -DistDir $DistDir }
    Write-Ok '차단을 풀었어요'

    $plan = @(Get-InstallPlan -BundleDir (Join-Path $DistDir 'bundle'))
    $i = 0
    foreach ($step in $plan) {
        $i++
        # 옛 윈도우(1803 미만)는 per-user 글꼴을 지원하지 않는다.
        # 넣으려 하면 조용히 실패하거나 관리자 권한을 묻는다. 그냥 건너뛴다.
        # 글꼴이 없어도 캠프는 전부 돌아간다. 화면 글씨체만 기본이 된다.
        if ($step.Kind -eq 'font' -and (Test-CampLegacy -DistDir $DistDir)) {
            Write-Ok ("$i/$($plan.Count) " + $step.Name + ' 은(는) 이 윈도우에서 건너뛸게요')
            continue
        }
        if ($step.AlreadyInstalled) {
            Write-Ok ("$i/$($plan.Count) " + $step.Name + ' 은(는) 이미 있어요. 넘어갈게요')
            continue
        }
        Write-Step ("$i/$($plan.Count) " + $step.Name + ' 을(를) 설치하고 있어요')
        if ($DryRun) {
            Write-Note ('  (연습) ' + $step.File + ' ' + ($step.Args -join ' '))
            continue
        }

        if ($step.Kind -eq 'font') {
            Install-Font -ZipPath $step.Path
        }
        elseif ($step.Kind -eq 'ghzip') {
            if (-not (Install-GithubCli -ZipPath $step.Path)) {
                Write-Fail ($step.Name + ' 설치에 실패했어요.')
                return 1
            }
        }
        elseif ($step.Kind -eq 'clizip') {
            if (-not (Install-OpencodeCli -ZipPath $step.Path)) {
                Write-Fail ($step.Name + ' 설치에 실패했어요.')
                return 1
            }
        }
        elseif ($step.Kind -eq 'msi') {
            # 함정(실측): Start-Process -ArgumentList 는 배열을 공백으로 이어붙이고
            # 인용을 안 해준다. 사용자 이름에 공백이 있으면 경로가 두 토막으로
            # 쪼개져 msiexec 이 앞부분만 패키지로 읽고 1619 로 죽는다.
            $인용 = '"' + $step.Path + '"'
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/i', $인용) + $step.Args) -PassThru -Wait
            if (-not (Test-InstallExitOk $p.ExitCode)) {
                # 여기서 멈추면 안 된다 (실측, 2026-09-05 행사장).
                #
                # 이 msi 는 노드 하나뿐인데, 패키지 안을 열어 보면 설치 위치가
                # ProgramFiles64Folder 로 박혀 있다. ALLUSERS=0 을 줘도 폴더는
                # C:\Program Files
odejs 다. 관리자 권한이 없으면 반드시 실패한다.
                #
                # 그런데 캠프 도구는 노드를 한 번도 쓰지 않는다. 앱은 Electron 이
                # 자기 노드를 품고 있고, CLI 는 단일 실행 파일이고, .sh 도구는
                # 파이썬과 ffmpeg 만 쓴다. 이것 하나 때문에 return 1 을 하면
                # 파이썬·Git·앱·프리셋·바탕화면 아이콘이 전부 안 깔린다.
                # 그게 "설치했는데 바탕화면에 아무것도 없어요" 의 정체다.
                Write-Note ($step.Name + ' 은(는) 못 넣었어요. 나머지는 계속할게요.')
                continue
            }
        }
        else {
            $p = Start-Process -FilePath $step.Path -ArgumentList $step.Args -PassThru -Wait
            if (-not (Test-InstallExitOk $p.ExitCode)) {
                Write-Fail ($step.Name + ' 설치에 실패했어요.'); return 1
            }
        }
        Write-Ok ($step.Name + ' 을(를) 설치했어요')
    }

    # 방금 깐 파이썬·Git 을 이 프로세스도 알아보게 한다. 자체 점검이
    # 바로 뒤에 돌기 때문에 여기서 해야 한다.
    if (-not $DryRun) { Update-CampPath }

    Write-Step '만들기 도구를 넣고 있어요'
    if (-not $DryRun) {
        if (-not (Install-CampTools -DistDir $DistDir)) {
            Write-Fail '만들기 도구를 넣지 못했어요. 이게 없으면 그림을 만들 수 없어요.'
            return 1
        }
    }
    Write-Ok '만들기 도구를 넣었어요'

    Write-Step '캠프 설정을 넣고 있어요'
    if (-not $DryRun) { Copy-PresetAndSecrets -DistDir $DistDir }
    Write-Ok '캠프 설정을 넣었어요'

    if (-not $DryRun) {
        # 진행 문구를 작업 뒤에 찍으면, 파일 3600개를 푸는 1분 동안 화면이
        # 멈춘 것처럼 보인다. 학생은 거기서 창을 닫고 다시 누른다. 먼저 찍는다.
        if (Test-Path -LiteralPath (Join-Path $DistDir 'offline') -PathType Container) {
            Write-Step '인터넷 없이 쓸 수 있게 준비물을 넣고 있어요 (1분쯤 걸려요)'
        }
        $푼것 = Restore-OfflineCache -DistDir $DistDir
        if ($null -ne $푼것) { Write-Ok ('준비물을 넣었어요 (' + $푼것 + '개)') }
    }

    Write-Step '.sh 도구를 실행할 셸을 잡고 있어요'
    if (-not $DryRun) {
        $cfg = Join-Path $env:USERPROFILE '.config'
        $cfg = Join-Path $cfg 'opencode'
        $cfg = Join-Path $cfg 'opencode.json'
        if (Set-CampShell -ConfigPath $cfg) { Write-Ok '셸을 잡았어요' }
        else { Write-Fail '셸을 잡지 못했어요. 그림 만들기가 안 될 수 있어요.' }
    }
    else { Write-Ok '셸을 잡았어요' }

    Write-Step '자동 업데이트를 꺼 두고 있어요'
    if (-not $DryRun) {
        if (Disable-AppAutoUpdate) { Write-Ok '캠프 때까지 이 버전으로 고정했어요' }
        else { Write-Note '자동 업데이트를 끄지 못했어요. 큰 문제는 아닙니다.' }
    }
    else { Write-Ok '자동 업데이트를 껐어요' }

    Write-Step '바탕화면에 아이콘을 놓고 있어요'
    if (-not $DryRun) {
        $n = New-CampShortcuts -DistDir $DistDir
        if ($n -ge 1) { Write-Ok ('바탕화면에 아이콘 ' + $n + '개를 놓았어요') }
        else { Write-Fail '바탕화면에 아이콘을 놓지 못했어요. 설치하기를 다시 실행해 주세요.' }
    }
    else { Write-Ok '바탕화면에 아이콘을 놓았어요' }

    Write-Step '연습 폴더를 만들고 있어요'
    if (-not $DryRun) {
        $parent = Join-Path $env:USERPROFILE '창의디자인캠프'
        $practice = Join-Path $parent '연습'
        if (-not (Test-Path -LiteralPath $practice)) {
            New-Item -ItemType Directory -Path $practice -Force | Out-Null
            $tpl = Join-Path $DistDir 'template'
            if (Test-Path -LiteralPath $tpl -PathType Container) {
                Copy-Item -Path (Join-Path $tpl '*') -Destination $practice -Recurse -Force
            }
        }
        Add-RegisteredProject -Path $practice | Out-Null
        Set-OnboardingComplete | Out-Null
    }
    Write-Ok '연습 폴더를 만들었어요'

    if ($SkipSelfCheck) { return 0 }

    Write-Host ''
    return (Invoke-SelfCheck)
}

# .cmd 진입점이 부르는 함수.
#
# 왜 한국어가 .cmd 가 아니라 여기 있는가: cmd.exe 는 UTF-8 배치 파일의
# 비ASCII 문자를 잘못 파싱한다(chcp 65001 을 넣어도 바이트 오프셋이 어긋나
# 명령이 쪼개진다). 실측으로 확인했다. 그래서 .cmd 는 순수 ASCII 로만 두고
# 학생이 읽는 모든 문장을 PowerShell 쪽에 둔다.
function Start-CampInstall([string]$DistDir) {
    $logPath = Join-Path $env:USERPROFILE '창의디자인캠프\설치기록.txt'
    Start-CampLog $logPath

    Write-Host ''
    Write-Host '  창의디자인캠프 준비를 시작합니다.'
    Write-Host '  10분쯤 걸려요. 창을 닫지 말고 기다려 주세요.'
    Write-Host ''

    $rc = Invoke-Install -DistDir $DistDir

    Write-Host ''
    if ($rc -eq 0) {
        Write-Host '  준비 끝! 캠프 당일에 "캠프시작" 을 눌러 주세요.'
    }
    else {
        Write-Host '  준비가 다 안 됐어요. 하지만 괜찮아요.'
        Write-Host '  여기서 그만하고, 캠프 첫날 아침에 그냥 오세요.'
        Write-Host '  5분이면 고쳐 드립니다.'
        Write-Host ('  기록 파일: ' + $logPath)
    }
    Write-Host ''

    Stop-CampLog
    return $rc
}
