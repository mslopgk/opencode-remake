# 캠프 당일 아침에 학생이 실행한다.
#
# 아무것도 묻지 않는다. 작업 폴더를 만들고 앱을 열어 준다.
# 조 번호와 팀 이름은 도우미가 대화하다가 물어서 우리팀.md 에 적는다 —
# 시작하자마자 칸 두 개를 채우게 하면 초등학교 5학년은 거기서 막힌다.

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
        [string]$Parent,
        [string]$TemplateDir,
        [switch]$NoLaunch
    )

    $result = @{ Ok = $false; Dir = $null; Registered = $false }

    # $Parent 가 비어 있으면 바탕화면에 만든다 (New-WorkFolder 가 정한다)
    $dir = New-WorkFolder -Parent $Parent -TemplateDir $TemplateDir
    if ($null -eq $dir) {
        Write-Fail '작업 폴더를 만들지 못했어요. 설치하기를 다시 실행해 주세요.'
        return $result
    }
    $result.Dir = $dir
    $result.Ok = $true
    Write-Ok '작업 폴더를 준비했어요.'

    $reg = Add-RegisteredProject -Path $dir
    $onb = Set-OnboardingComplete
    if ($reg) {
        $result.Registered = $true
        Write-Ok '앱에 등록했어요.'
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
            Write-Ok '앱이 열렸어요! 도우미에게 그냥 말을 걸어 보세요.'
        }
    }

    return $result
}

function Start-CampLauncher {
    param([string]$TemplateDir)

    # 기록 파일은 바탕화면을 어지럽히지 않게 사용자 폴더에 둔다.
    # 작업 폴더만 바탕화면에 만든다 (학생이 눈으로 찾을 수 있어야 한다).
    $logDir = Join-Path $env:USERPROFILE '창의디자인캠프'
    Start-CampLog (Join-Path $logDir '시작기록.txt')

    Write-Step '창의디자인캠프를 시작합니다!'
    Write-Host ''

    $r = Invoke-Launcher -Parent '' -TemplateDir $TemplateDir
    Stop-CampLog
    if ($r.Ok) { return 0 } else { return 1 }
}
