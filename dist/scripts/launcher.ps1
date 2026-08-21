# 캠프 당일 아침에 학생이 실행한다.
# 팀 배정이 당일이라 설치 시점에는 팀 폴더를 만들 수 없다. 그 간극을 메운다.

function Get-DesktopAppPath {
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop'
    if (Test-Path -LiteralPath $dir -PathType Container) {
        # 실측: 앱 실행파일 이름은 OpenCode.exe 다. 제거 프로그램은 걸러낸다.
        $exe = Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File |
               Where-Object { $_.Name -notmatch 'nins' } |
               Select-Object -First 1
        if ($null -ne $exe) { return $exe.FullName }
    }
    return $null
}

function Invoke-Launcher {
    param(
        [int]$Number,
        [string]$Name,
        [string]$Parent,
        [string]$TemplateDir,
        [switch]$NoLaunch
    )

    $result = @{ Ok = $false; Dir = $null; Registered = $false }

    $dir = New-TeamFolder -Number $Number -Name $Name -Parent $Parent -TemplateDir $TemplateDir
    if ($null -eq $dir) {
        Write-Fail '조 번호는 1부터 15까지, 팀 이름에는 특수문자를 쓸 수 없어요.'
        return $result
    }
    $result.Dir = $dir
    $result.Ok = $true
    Write-Ok ('우리 팀 폴더를 만들었어요: ' + (Split-Path -Leaf $dir))

    $reg = Add-RegisteredProject -Path $dir
    $onb = Set-OnboardingComplete
    if ($reg) {
        $result.Registered = $true
        Write-Ok '앱에 우리 팀을 등록했어요.'
    }
    else {
        Write-Note '앱에 자동 등록이 안 됐어요. 앱이 열리면 "프로젝트 추가" 를 눌러'
        Write-Note ('  ' + $dir + ' 를 골라 주세요.')
    }
    if (-not $onb) {
        Write-Note '앱 첫 화면 안내를 건너뛰지 못했어요. 그냥 넘기면 됩니다.'
    }

    if (-not $NoLaunch) {
        $app = Get-DesktopAppPath
        if ($null -eq $app) {
            Write-Fail '앱을 찾을 수 없어요. 설치하기를 다시 실행해 주세요.'
        }
        else {
            Write-Step '앱을 열고 있어요...'
            Start-Process -FilePath $app | Out-Null
            Write-Ok '앱이 열렸어요! 이제 /시작 이라고 써 보세요.'
        }
    }

    return $result
}

function Start-CampLauncher([string]$TemplateDir) {
    $parent = Join-Path $env:USERPROFILE '창의디자인캠프'
    Start-CampLog (Join-Path $parent '시작기록.txt')

    Write-Step '창의디자인캠프를 시작합니다!'
    Write-Host ''
    $numText = Read-Host '우리는 몇 조예요? (1~15 숫자만)'
    $teamName = Read-Host '우리 팀 이름은 뭐예요?'

    $num = 0
    if (-not [int]::TryParse($numText, [ref]$num)) {
        Write-Fail '조 번호는 숫자로 써 주세요.'
        Stop-CampLog
        return 1
    }

    $r = Invoke-Launcher -Number $num -Name $teamName -Parent $parent -TemplateDir $TemplateDir
    Stop-CampLog
    if ($r.Ok) { return 0 } else { return 1 }
}
