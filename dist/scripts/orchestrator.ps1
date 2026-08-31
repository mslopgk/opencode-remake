# 캠프 배포판 설치 오케스트레이터.
#
# 핵심 설계: 우리가 인스톨러를 만드는 게 아니라, 이미 코드 서명된 공식
# 인스톨러들을 조용히 순차 실행한다. 그래서 서명 인증서가 필요 없다.
# 모든 구성요소는 per-user 로 설치해 관리자 권한을 요구하지 않는다.

function Test-Prerequisites {
    $reasons = @()

    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]($os.BuildNumber) -lt 19041) {
        $reasons += 'Windows 10 (2004) 이상이 필요해요.'
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        $reasons += ('64비트 Windows 가 필요해요. (지금: ' + $env:PROCESSOR_ARCHITECTURE + ')')
    }
    # 필요 공간: 번들 350MB + 설치되는 구성요소 약 1.5GB + 작업 공간.
    # 5GB 를 요구했더니 디스크가 거의 찬 노트북에서 이유 없이 막혔다(실측).
    $needGb = 2.5
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

function Unblock-BundleFiles([string]$DistDir) {
    # USB·다운로드로 온 파일에는 차단 플래그가 붙는다.
    # 이걸 안 떼면 60대에서 전부 막힌다.
    Get-ChildItem -LiteralPath $DistDir -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
}

# 이미 설치돼 있으면 건너뛴다.
#
# 두 가지 이유로 필요하다:
#  1) 학생 노트북에 이미 Node 나 Git 이 있으면 다시 깔 이유가 없다 (설치 시간 단축)
#  2) 이미 쓰던 버전을 우리가 덮어써서 학생·개발자 환경을 망치지 않는다
function Test-ComponentInstalled([string]$Kind, [string]$File) {
    if ($env:CAMP_FORCE_INSTALL_ALL -eq '1') { return $false }

    if ($File -eq 'node-lts-x64.msi') {
        return ($null -ne (Get-Command 'node.exe' -CommandType Application -ErrorAction SilentlyContinue))
    }
    if ($File -eq 'python-3.12-amd64.exe') {
        return ($null -ne (Get-Command 'python.exe' -CommandType Application -ErrorAction SilentlyContinue))
    }
    if ($File -eq 'Git-64-bit.exe') {
        return ($null -ne (Get-Command 'git.exe' -CommandType Application -ErrorAction SilentlyContinue))
    }
    if ($Kind -eq 'font') {
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $key)) { return $false }
        $props = (Get-ItemProperty -Path $key).PSObject.Properties.Name
        # 실측 함정: Nerd Font 는 Cascadia 를 "CaskaydiaCove" 로 이름을 바꾼다.
        # Cascadia 만 찾으면 이미 설치된 것을 못 알아보고 재설치하다가
        # "파일이 사용 중" 오류가 난다.
        foreach ($n in $props) {
            if ($n -like '*Caskaydia*' -or $n -like '*Cascadia*') { return $true }
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

function Copy-PresetAndSecrets([string]$DistDir) {
    # 프리셋
    $presetSrc = Join-Path $DistDir 'preset'
    $presetDst = Join-Path $env:USERPROFILE '.config\opencode'
    if (Test-Path -LiteralPath $presetSrc -PathType Container) {
        if ((Test-Path -LiteralPath $presetDst) -and (@(Get-ChildItem -LiteralPath $presetDst -Force)).Count -gt 0) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Move-Item -LiteralPath $presetDst -Destination ($presetDst + '.backup-' + $stamp)
            Write-Note '원래 쓰던 설정은 따로 보관했어요.'
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
    $pre = Test-Prerequisites
    if (-not $pre.Ok) {
        foreach ($r in $pre.Reasons) { Write-Fail $r }
        return 1
    }
    Write-Ok '컴퓨터는 괜찮아요'

    Write-Step '파일 차단을 풀고 있어요'
    if (-not $DryRun) { Unblock-BundleFiles -DistDir $DistDir }
    Write-Ok '차단을 풀었어요'

    $plan = @(Get-InstallPlan -BundleDir (Join-Path $DistDir 'bundle'))
    $i = 0
    foreach ($step in $plan) {
        $i++
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
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/i', $step.Path) + $step.Args) -PassThru -Wait
            if ($p.ExitCode -ne 0) { Write-Fail ($step.Name + ' 설치에 실패했어요.'); return 1 }
        }
        else {
            $p = Start-Process -FilePath $step.Path -ArgumentList $step.Args -PassThru -Wait
            if ($p.ExitCode -ne 0) { Write-Fail ($step.Name + ' 설치에 실패했어요.'); return 1 }
        }
        Write-Ok ($step.Name + ' 을(를) 설치했어요')
    }

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
        Write-Host '  준비가 다 안 됐어요. 선생님을 불러 주세요.'
        Write-Host ('  기록 파일: ' + $logPath)
    }
    Write-Host ''

    Stop-CampLog
    return $rc
}
