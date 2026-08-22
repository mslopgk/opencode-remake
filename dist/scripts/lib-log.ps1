# 학생·멘토가 읽는 한국어 로그. 화면과 파일에 동시에 남긴다.
#
# 주의: Set-Content/Add-Content 는 Windows PowerShell 5.1 에서 기본 인코딩이
# ANSI 라 한국어가 깨진다. 반드시 -Encoding utf8 을 붙인다.
$script:CampLogPath = $null

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

function Write-CampLine([string]$Line, [string]$Color) {
    if ($Color) { Write-Host $Line -ForegroundColor $Color } else { Write-Host $Line }
    if ($null -ne $script:CampLogPath) {
        Add-Content -LiteralPath $script:CampLogPath -Value $Line -Encoding utf8
    }
}

function Write-Step([string]$Msg) { Write-CampLine ("[진행] " + $Msg) 'Cyan' }
function Write-Ok([string]$Msg)   { Write-CampLine ("[완료] " + $Msg) 'Green' }
function Write-Fail([string]$Msg) { Write-CampLine ("[실패] " + $Msg) 'Red' }
function Write-Note([string]$Msg) { Write-CampLine ("[안내] " + $Msg) 'Yellow' }
