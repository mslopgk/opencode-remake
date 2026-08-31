$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\dist\scripts\lib-log.ps1"
. "$Repo\dist\scripts\selfcheck.ps1"

# 가짜 모드에서 모두 성공
$env:CAMP_SELFCHECK_FAKE = 'ok'
try {
    Assert-True (Test-OpencodeVersion -Expected '1.18.20') '가짜 모드: 버전 통과'
    $p = Test-PresetLoaded -Port 4321
    Assert-True $p.Ok '가짜 모드: 프리셋 통과'
    Assert-Eq $p.Agents 4 '가짜 모드: 에이전트 4'
    Assert-Eq $p.Commands 12 '가짜 모드: 명령어 12'
    Assert-True (Test-DeepSeek) '가짜 모드: DeepSeek 통과'
    $h = Test-MediaKeys
    Assert-True $h.Ok '가짜 모드: 그림 만들기 열쇠 통과'
    Assert-True (Test-CampTools).Ok '가짜 모드: 만들기 도구 통과'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

# 가짜 모드에서 모두 실패
$env:CAMP_SELFCHECK_FAKE = 'fail'
try {
    Assert-Eq (Test-OpencodeVersion -Expected '1.18.20') $false '가짜 모드: 버전 실패'
    Assert-Eq (Test-PresetLoaded -Port 4321).Ok $false '가짜 모드: 프리셋 실패'
    Assert-Eq (Test-DeepSeek) $false '가짜 모드: DeepSeek 실패'
    Assert-Eq (Test-MediaKeys).Ok $false '가짜 모드: 그림 만들기 열쇠 실패'
    Assert-Eq (Test-CampTools).Ok $false '가짜 모드: 만들기 도구 실패'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

# 통과 조건이 4/10 으로 고정되어 있는지 (3/10 이면 실패해야 한다)
$env:CAMP_SELFCHECK_FAKE = 'partial'
try {
    $p2 = Test-PresetLoaded -Port 4321
    Assert-Eq $p2.Ok $false '에이전트가 부족하면 실패로 판정'
    Assert-Eq $p2.Agents 3 '부분 모드는 에이전트 3'
}
finally { Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue }

# Invoke-SelfCheck 가 전부 통과면 0, 하나라도 실패면 1
$tmp = Join-Path $env:TEMP ("campsc-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $env:CAMP_SELFCHECK_FAKE = 'ok'
    Start-CampLog (Join-Path $tmp 'ok.txt')
    Assert-Eq (Invoke-SelfCheck) 0 '전부 통과면 0 반환'
    Stop-CampLog
    $okLog = Get-Content -LiteralPath (Join-Path $tmp 'ok.txt') -Raw -Encoding UTF8
    Assert-Contains $okLog '준비 끝' '성공 안내가 로그에 남음'

    $env:CAMP_SELFCHECK_FAKE = 'fail'
    Start-CampLog (Join-Path $tmp 'fail.txt')
    Assert-Eq (Invoke-SelfCheck) 1 '하나라도 실패면 1 반환'
    Stop-CampLog
    $failLog = Get-Content -LiteralPath (Join-Path $tmp 'fail.txt') -Raw -Encoding UTF8
    Assert-Contains $failLog '안 된 것' '실패 목록이 로그에 남음'
    Assert-Contains $failLog '선생님' '학생에게 도움 요청 안내'
}
finally {
    Remove-Item Env:\CAMP_SELFCHECK_FAKE -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# 회귀 방지: Invoke-RestMethod 는 PowerShell 5.1 에서 charset 없는 응답을
# ISO-8859-1 로 디코딩해 한국어 이름을 깨뜨린다(실측 확인). 쓰면 안 된다.
$scSrc = Get-Content -LiteralPath (Join-Path $Repo 'dist\scripts\selfcheck.ps1') -Raw -Encoding UTF8
# 주석에는 등장해도 된다(왜 안 쓰는지 설명). '호출'이 없어야 한다
Assert-NotContains $scSrc 'Invoke-RestMethod -Uri' 'selfcheck 가 Invoke-RestMethod 를 호출하지 않음'
Assert-Contains $scSrc 'Get-JsonUtf8' 'selfcheck 가 UTF-8 디코딩 헬퍼를 씀'
Assert-Contains $scSrc '[System.Text.Encoding]::UTF8' '명시적 UTF-8 인코딩 설정'

# 도구 점검이 실제로 존재해야 한다 (이 점검이 없어서 배포 누락을 놓쳤다)
Assert-Contains $scSrc 'function Test-CampTools' '도구 점검 함수 존재'
Assert-Contains $scSrc 'camp-media.sh' '도구 점검이 camp-media.sh 를 확인'
Assert-Contains $scSrc 'merge-slides.sh' '도구 점검이 merge-slides.sh 를 확인'

if (Test-Summary) { exit 0 } else { exit 1 }
