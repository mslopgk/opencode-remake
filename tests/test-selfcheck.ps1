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
    Assert-Eq $p.Commands 11 '가짜 모드: 명령어 11'
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
    # 집에서 미리 설치하는 경우가 많다. "선생님을 불러라" 만으로는 쓸 수 없다.
    # 스스로 해 볼 수 있는 절차와 연락 경로를 둘 다 줘야 한다.
    Assert-Contains $failLog '다시 실행' '스스로 해 볼 절차를 안내'
    Assert-Contains $failLog '인터넷' '인터넷 확인을 먼저 안내'
    Assert-Contains $failLog '기록 파일' '기록 파일 위치를 알려 줌'
    # 문의 창구를 두지 않는다. 혼자 붙들고 있게 하지 않고 캠프 당일에 처리한다.
    Assert-Contains $failLog '그만하세요' '두 번 실패하면 그만하라고 말한다'
    Assert-Contains $failLog '그냥 오시면' '캠프 당일 처리를 안내'
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


# ── 점검 목록이 실제 파일과 일치하는지 ──────────────────────────
# 음악 명령을 지웠을 때 이 목록을 안 고쳐서 "명령 10/11" 로 실기기에서
# 빨간불이 났다. 목록과 파일이 어긋나면 여기서 잡는다.
$cmdDir = Join-Path $Repo 'camp-preset\command'
$onDisk = @(Get-ChildItem (Join-Path $cmdDir '*.md') | ForEach-Object { $_.BaseName } | Sort-Object)
$inList = @($script:CommandNames | Sort-Object)

Assert-Eq $onDisk.Count $script:ExpectedCommands '기대 개수가 실제 파일 수와 같다'
Assert-Eq ($inList -join ',') ($onDisk -join ',') '점검 목록이 실제 명령 파일과 일치'

$agentDir = Join-Path $Repo 'camp-preset\agent'
$agentsOnDisk = @(Get-ChildItem (Join-Path $agentDir '*.md') | ForEach-Object { $_.BaseName } | Sort-Object)
Assert-Eq $agentsOnDisk.Count $script:ExpectedAgents '기대 에이전트 수가 실제 파일 수와 같다'
Assert-Eq (($script:AgentNames | Sort-Object) -join ',') ($agentsOnDisk -join ',') '에이전트 목록이 실제 파일과 일치'

if (Test-Summary) { exit 0 } else { exit 1 }
