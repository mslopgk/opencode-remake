# 학생·멘토가 읽는 한국어 로그. 화면과 파일에 동시에 남긴다.
#
# 주의: Set-Content/Add-Content 는 Windows PowerShell 5.1 에서 기본 인코딩이
# ANSI 라 한국어가 깨진다. 반드시 -Encoding utf8 을 붙인다.
$script:CampLogPath = $null

# GUI 가 로그를 받아 화면에 그리기 위한 통로.
# 이 싱크가 있으면 orchestrator/selfcheck/launcher 를 한 줄도 고치지 않고
# 그대로 GUI 에서 재사용할 수 있다.
$script:CampLogSink = $null

function Set-CampLogSink([scriptblock]$Sink) { $script:CampLogSink = $Sink }
function Clear-CampLogSink { $script:CampLogSink = $null }

function Start-CampLog([string]$Path) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $script:CampLogPath = $Path
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $Path -Value ("===== 기록 시작 " + $stamp + " =====") -Encoding utf8
}

function Stop-CampLog {
    if ($null -ne $script:CampLogPath) {
        Add-Content -LiteralPath $script:CampLogPath -Value "===== 기록 끝 =====" -Encoding utf8
    }
    $script:CampLogPath = $null
}

function Write-CampLine([string]$Line, [string]$Color, [string]$Level, [string]$Bare) {
    if ($null -eq $script:CampLogSink) {
        if ($Color) { Write-Host $Line -ForegroundColor $Color } else { Write-Host $Line }
    }
    else {
        # GUI 가 붙어 있으면 화면에는 찍지 않고 싱크로 넘긴다.
        # 싱크에서 예외가 나도 설치를 멈추지 않는다.
        try { & $script:CampLogSink $Level $Bare } catch { }
    }
    if ($null -ne $script:CampLogPath) {
        Add-Content -LiteralPath $script:CampLogPath -Value $Line -Encoding utf8
    }
}

function Write-Step([string]$Msg) { Write-CampLine ("[진행] " + $Msg) 'Cyan'   'step' $Msg }
function Write-Ok([string]$Msg)   { Write-CampLine ("[완료] " + $Msg) 'Green'  'ok'   $Msg }
function Write-Fail([string]$Msg) { Write-CampLine ("[실패] " + $Msg) 'Red'    'fail' $Msg }
function Write-Note([string]$Msg) { Write-CampLine ("[안내] " + $Msg) 'Yellow' 'note' $Msg }
