# opencode 데스크탑 앱의 상태 파일을 다룬다.
#
# 실측(2026-08-21, v1.18.20)으로 확인한 구조:
#   %APPDATA%\ai.opencode.desktop\opencode.global.dat
#     → 최상위 JSON 객체. "server" 키의 값이 "JSON 문자열"이고
#       그것을 파싱하면 {"list":[],"projects":{"local":[{"worktree":"..."}]}}
#   %APPDATA%\ai.opencode.desktop\opencode.settings
#     → 최상위 JSON 객체. firstLaunchOnboardingComplete 로 온보딩을 건너뛴다
#
# 손상된 파일은 절대 덮어쓰지 않는다. 앱 상태를 망가뜨리는 것이
# 등록 실패보다 훨씬 나쁘다.

# JSON 을 BOM 없이 쓴다.
#
# 왜 반드시 BOM 이 없어야 하는가 (실측 사고, student 계정 2026-09-01):
#   PowerShell 5.1 의 `Set-Content -Encoding utf8` 은 파일 앞에
#   EF BB BF (BOM) 를 붙인다. 우리가 읽을 때는 Get-Content -Encoding UTF8 이
#   BOM 을 알아서 떼주므로 우리 테스트는 전부 통과했다.
#
#   그런데 앱은 electron-store 로 이 파일을 읽는다. 그 코드는
#     get store() { try { JSON.parse(readFileSync(...,'utf8')) } catch(e) {
#       if (e.code==='ENOENT') ...
#       if (this.#options.clearInvalidConfig) ...   // 기본값 false
#       throw error;                                // 그냥 던진다
#     } }
#   이고 생성자가 곧바로 this.store 를 읽는다. BOM 이 있으면
#   JSON.parse 가 SyntaxError 를 던져 앱이 창을 만들기 전에 죽는다.
#   증상: "캠프 시작" 을 눌러도 아무 일도 안 일어난다.
#   런처 기록에는 "앱이 열렸어요!" 가 찍힌다 (확인을 안 했으므로).
#
# 그래서 BOM 없는 UTF-8 로만 쓴다. Set-Content 를 쓰지 마라.
function Write-JsonNoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-AppStateDir {
    if ($env:CAMP_APPSTATE_DIR) { return $env:CAMP_APPSTATE_DIR }
    return (Join-Path $env:APPDATA 'ai.opencode.desktop')
}

function Read-JsonFile([string]$Path) {
    # 성공하면 객체, 파일이 없으면 $null, 손상되면 문자열 'BROKEN'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return 'BROKEN' }
}

function Get-ServerBlob($GlobalObj) {
    # server 키의 값(JSON 문자열)을 객체로. 없으면 기본 골격을 만든다
    if ($null -ne $GlobalObj -and $GlobalObj.PSObject.Properties.Name -contains 'server') {
        try { return ($GlobalObj.server | ConvertFrom-Json) } catch { return 'BROKEN' }
    }
    return ('{"list":[],"projects":{"local":[]}}' | ConvertFrom-Json)
}

function Get-RegisteredProjects {
    $path = Join-Path (Get-AppStateDir) 'opencode.global.dat'
    $g = Read-JsonFile $path
    if ($g -is [string]) { return @() }          # 손상
    $server = Get-ServerBlob $g
    if ($server -is [string]) { return @() }     # 손상
    $out = @()
    if ($null -ne $server.projects -and $null -ne $server.projects.local) {
        foreach ($p in @($server.projects.local)) {
            if ($null -ne $p -and $p.worktree) { $out += [string]$p.worktree }
        }
    }
    return $out
}

function Add-RegisteredProject([Parameter(Mandatory=$true)][string]$Path) {
    $dir = Get-AppStateDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $file = Join-Path $dir 'opencode.global.dat'

    $g = Read-JsonFile $file
    if ($g -is [string]) { return $false }       # 손상 — 덮어쓰지 않는다
    if ($null -eq $g) { $g = ('{}' | ConvertFrom-Json) }

    $server = Get-ServerBlob $g
    if ($server -is [string]) { return $false }

    if ($null -eq $server.projects) {
        $server | Add-Member -NotePropertyName 'projects' -NotePropertyValue ('{"local":[]}' | ConvertFrom-Json) -Force
    }
    if ($null -eq $server.projects.local) {
        $server.projects | Add-Member -NotePropertyName 'local' -NotePropertyValue @() -Force
    }

    $existing = @()
    foreach ($p in @($server.projects.local)) {
        if ($null -ne $p -and $p.worktree) { $existing += [string]$p.worktree }
    }
    if ($existing -contains $Path) { return $true }   # 이미 있음 — 멱등

    $entry = New-Object psobject
    $entry | Add-Member -NotePropertyName 'worktree' -NotePropertyValue $Path
    $entry | Add-Member -NotePropertyName 'expanded' -NotePropertyValue $true
    $server.projects.local = @($server.projects.local) + @($entry)

    $g | Add-Member -NotePropertyName 'server' -NotePropertyValue ($server | ConvertTo-Json -Depth 20 -Compress) -Force
    Write-JsonNoBom -Path $file -Text ($g | ConvertTo-Json -Depth 20)
    return $true
}

function Set-OnboardingComplete {
    $dir = Get-AppStateDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $file = Join-Path $dir 'opencode.settings'

    $s = Read-JsonFile $file
    if ($s -is [string]) { return $false }       # 손상 — 덮어쓰지 않는다
    if ($null -eq $s) { $s = ('{}' | ConvertFrom-Json) }

    $s | Add-Member -NotePropertyName 'firstLaunchOnboardingComplete' -NotePropertyValue $true -Force
    Write-JsonNoBom -Path $file -Text ($s | ConvertTo-Json -Depth 20)
    return $true
}
