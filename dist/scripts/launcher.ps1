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

# 앱을 열고, 창이 진짜 떴는지 확인한다.
#
# 왜 확인이 필요한가 (실측 사고, student 계정 2026-09-01):
#   Start-Process 는 프로그램을 띄우는 데 성공하면 바로 돌아온다.
#   그 프로그램이 창을 못 만들어도 성공이다. 그래서 앱이 설정 파일을
#   읽다가 멈춘 상황에서도 기록에는 "앱이 열렸어요!" 가 찍혔다.
#   학생은 아무 일도 일어나지 않는 화면만 본다. 가장 나쁜 실패다.
#
# 왜 "프로세스가 살아 있는지" 로는 부족한가:
#   실측한 실패는 프로세스가 죽는 게 아니라 창 없이 매달리는 것이었다.
#   학생이 다섯 번 누르니 창 없는 프로세스가 15개 쌓여 있었다.
#   그래서 창 손잡이(MainWindowHandle)가 0 이 아닌 것이 있는지를 본다.
#   실측 A/B: 설정에 BOM 이 있으면 프로세스 3개·창 0개,
#             BOM 을 떼면 프로세스 6개·창 1개("OpenCode").
#
# 왜 내가 띄운 프로세스만 보면 안 되는가:
#   앱이 이미 켜져 있으면, 두 번째로 띄운 프로세스는 기존 창에
#   알리고 스스로 끝난다. 그건 정상이다. 그래서 이름으로 전체를 본다.
$script:CampAppWindow = [IntPtr]::Zero

function Test-AppOpened([string]$AppPath, [int]$WaitSeconds = 25) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($AppPath)
    $mySession = (Get-Process -Id $PID).SessionId
    try { Start-Process -FilePath $AppPath | Out-Null }
    catch { return $false }

    # 느린 노트북에서 일렉트론 창이 뜨는 데 20초 넘게 걸리는 것도 봤다.
    # 창이 보이면 즉시 통과하므로, 기다리는 상한만 넉넉하게 둔다.
    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        Start-Sleep -Seconds 1
        $창있음 = @(Get-Process -Name $name -ErrorAction SilentlyContinue |
                    Where-Object { $_.SessionId -eq $mySession -and $_.MainWindowHandle -ne 0 })
        if ($창있음.Count -ge 1) {
            # 뒤에서 이 창의 단추를 눌러야 하므로 손잡이를 남겨 둔다
            $script:CampAppWindow = $창있음[0].MainWindowHandle
            return $true
        }
    }
    return $false
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
            $result.Ok = $false
            Write-Fail '앱을 찾을 수 없어요. 설치하기를 다시 실행해 주세요.'
        }
        else {
            Write-Step '앱을 열고 있어요...'
            if (Test-AppOpened -AppPath $app) {
                # 앱은 대화 화면이 아니라 목록 화면으로 열린다(실측).
                # 학생이 "세션" 을 눌러야 글 쓰는 칸이 나오는데, 그건
                # 초등학생에게 설명할 개념이 아니다. 우리가 대신 눌러 준다.
                # 실패해도 앱은 열려 있으므로 진행을 막지 않는다.
                # 도구를 고친 직후에는 반드시 새 대화로 시작한다.
                #
                # 왜 (2026-09-05 현장): 설정을 고쳐도 학생은 그 사실을 모르고
                # 열어 두었던 옛 대화를 그대로 이어 쓴다. 바뀐 것이 안 먹는
                # 것처럼 보인다. 말로 알려 주면 아무도 안 읽으므로 도구가 한다.
                $새대화표 = Join-Path (Join-Path $env:USERPROFILE '창의디자인캠프') '새대화필요.txt'
                $새로 = Test-Path -LiteralPath $새대화표 -PathType Leaf

                $열림 = $false
                try {
                    if ($새로) {
                        $열림 = Open-CampSession -Window $script:CampAppWindow -Project '내캠페인' -Force
                        Remove-Item -LiteralPath $새대화표 -Force -ErrorAction SilentlyContinue
                        Write-Note '고친 것이 적용되도록 새 대화를 열었어요.'
                    }
                    else {
                        $열림 = Open-CampSession -Window $script:CampAppWindow -Project '내캠페인'
                    }
                }
                catch { $열림 = $false }

                if ($열림) {
                    Write-Ok '앱이 열렸어요! 도우미에게 그냥 말을 걸어 보세요.'
                }
                else {
                    Write-Ok '앱이 열렸어요!'
                    Write-Note '글 쓰는 칸이 안 보이면 화면의 "새 세션" 을 한 번 누르세요.'
                }
            }
            else {
                # 실측 사고: 여기서 $result 를 안 건드려서, 앱이 안 떠도
                # 종료값이 0 이었다. 학생은 "시작해요!" 화면을 보고
                # 창이 닫히는 것만 봤다. 무엇이 잘못됐는지 알 방법이 없었다.
                $result.Ok = $false
                Write-Fail '앱이 열리지 않았어요.'
                Write-Note '창을 닫고 "캠프 시작" 을 한 번 더 눌러 보세요.'
                Write-Note '두 번 해도 안 되면 그냥 두고 캠프 날 오세요.'
            }
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
