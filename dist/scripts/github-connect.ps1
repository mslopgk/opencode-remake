# 깃허브 연결. 학생(보호자 계정)이 발표자료를 인터넷에 올릴 수 있게 한다.
#
# 왜 따로 있는가: 로그인은 한 번만 하면 되고, 브라우저를 오가는 대화형
# 절차라 채팅 안에서는 할 수 없다. 캠프 전날 집에서 보호자가 눌러 두면
# 당일에는 /올리기 만 쓰면 된다.

function Get-GhExe {
    if ($env:CAMP_GH_EXE) { return $env:CAMP_GH_EXE }
    $p = Join-Path $env:LOCALAPPDATA 'Programs\gh-cliin\gh.exe'
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    $onPath = Get-Command 'gh.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $onPath) { return $onPath.Source }
    return $null
}

# 이미 연결돼 있으면 $true.
function Test-GithubConnected {
    $gh = Get-GhExe
    if ($null -eq $gh) { return $false }
    # 5.1 에서 네이티브 exe 에 2>&1 을 쓰면 종료코드 0 에도 실패로 보인다(실측).
    # 출력은 파일로 받는다.
    $out = Join-Path $env:TEMP ('ghauth-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process -FilePath $gh -ArgumentList @('auth', 'status') -PassThru -Wait `
                -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
        return ($p.ExitCode -eq 0)
    }
    catch { return $false }
    finally {
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($out + '.err') -Force -ErrorAction SilentlyContinue
    }
}

# 연결된 계정 이름. 못 알아내면 $null.
function Get-GithubAccount {
    $gh = Get-GhExe
    if ($null -eq $gh) { return $null }
    $out = Join-Path $env:TEMP ('ghuser-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process -FilePath $gh -ArgumentList @('api', 'user', '-q', '.login') -PassThru -Wait `
                -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
        if ($p.ExitCode -ne 0) { return $null }
        $name = (Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        return $name.Trim()
    }
    catch { return $null }
    finally {
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($out + '.err') -Force -ErrorAction SilentlyContinue
    }
}

# 로그인 창(검은 창)을 띄운다. 학생이 브라우저에서 확인을 누르면 끝난다.
# 이 함수는 그 창이 닫힐 때까지 기다린다.
function Start-GithubLogin {
    $gh = Get-GhExe
    if ($null -eq $gh) { return $false }
    try {
        $p = Start-Process -FilePath $gh `
                -ArgumentList @('auth', 'login', '--hostname', 'github.com',
                                '--git-protocol', 'https', '--web') `
                -PassThru -Wait
        if ($p.ExitCode -ne 0) { return $false }
    }
    catch { return $false }

    # 올릴 때 암호를 다시 묻지 않도록 git 에 연결해 둔다
    try {
        Start-Process -FilePath $gh -ArgumentList @('auth', 'setup-git') -Wait -WindowStyle Hidden | Out-Null
    }
    catch { }

    return (Test-GithubConnected)
}

# 화면 없이 쓰는 진입점.
function Connect-CampGithub {
    if ($null -eq (Get-GhExe)) {
        Write-Fail '인터넷에 올리는 도구가 없어요. 설치하기를 먼저 실행해 주세요.'
        return 1
    }
    if (Test-GithubConnected) {
        $who = Get-GithubAccount
        if ($who) { Write-Ok ('이미 연결돼 있어요 (' + $who + ')') }
        else { Write-Ok '이미 연결돼 있어요' }
        return 0
    }
    Write-Step '깃허브에 연결할게요. 검은 창과 인터넷 창이 열려요.'
    if (Start-GithubLogin) {
        $who = Get-GithubAccount
        if ($who) { Write-Ok ('연결됐어요 (' + $who + ')') }
        else { Write-Ok '연결됐어요' }
        return 0
    }
    Write-Fail '연결하지 못했어요. 다시 해 보거나 선생님을 불러 주세요.'
    return 1
}
