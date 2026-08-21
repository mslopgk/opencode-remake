$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"

$tmp = Join-Path $env:TEMP ("camptest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $logPath = Join-Path $tmp 'log.txt'
    Start-CampLog $logPath

    Write-Step '설치를 시작합니다'
    Write-Ok '노드를 설치했어요'
    Write-Fail '그림 만들기 연결에 실패했어요'
    Write-Note '자세한 내용은 기록 파일을 보세요'

    Stop-CampLog

    Assert-FileExists $logPath '로그 파일이 만들어짐'
    $content = Get-Content -Path $logPath -Raw -Encoding UTF8
    Assert-Contains $content '설치를 시작합니다' '단계 로그가 기록됨'
    Assert-Contains $content '노드를 설치했어요' '성공 로그가 기록됨'
    Assert-Contains $content '그림 만들기 연결에 실패했어요' '실패 로그가 기록됨'
    Assert-Contains $content '자세한 내용은' '안내 로그가 기록됨'

    Assert-NotContains $content '?' '한국어가 깨지지 않음'

    Start-CampLog $logPath
    Write-Ok '두 번째 기록'
    Stop-CampLog
    $content2 = Get-Content -Path $logPath -Raw -Encoding UTF8
    Assert-Contains $content2 '두 번째 기록' '재시작 후에도 기록됨'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if (Test-Summary) { exit 0 } else { exit 1 }
