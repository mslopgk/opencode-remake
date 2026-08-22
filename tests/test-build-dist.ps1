$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"
. "$Repo\scripts\build-dist.ps1"

$rc = Invoke-BuildDist -RepoDir $Repo
Assert-Eq $rc 0 '빌드 성공'

Assert-FileExists (Join-Path $Repo 'dist\preset\AGENTS.md') '프리셋 AGENTS.md 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\opencode.json') '프리셋 설정 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\agent\도우미.md') '에이전트 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\command\도와줘.md') '명령어 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\preset\skills\web-slides\SKILL.md') '스킬 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\template\index.html') '템플릿 복사됨'
Assert-FileExists (Join-Path $Repo 'dist\template\우리팀.md') '팀 기록 파일 복사됨'

# opencode 가 만든 부산물은 배포판에 들어가면 안 된다
Assert-True (-not (Test-Path (Join-Path $Repo 'dist\preset\node_modules'))) 'node_modules 는 배포되지 않음'
Assert-True (-not (Test-Path (Join-Path $Repo 'dist\preset\package.json'))) 'package.json 은 배포되지 않음'

# 검증 함수가 결과를 돌려주는지
$v = Test-DistComplete -DistDir (Join-Path $Repo 'dist')
Assert-True ($null -ne $v.Missing) '검증이 결과를 반환'
Assert-True ($null -ne $v.Ok) '검증이 Ok 를 반환'

# 번들 소스 목록에 standalone CLI 가 들어 있어야 한다 (자체 점검에 필요)
. "$Repo\scripts\fetch-bundle.ps1"
$names = @()
foreach ($s in (Get-BundleSources)) { $names += $s.Name }
Assert-True ($names -contains 'opencode-windows-x64.zip') '번들에 standalone CLI 포함'
Assert-True ($names -contains 'opencode-desktop-win-x64.exe') '번들에 데스크탑 앱 포함'
Assert-Eq $names.Count 6 '번들 구성요소 6개'

# 모든 URL 이 https 인지
foreach ($s in (Get-BundleSources)) {
    Assert-True ($s.Url.StartsWith('https://')) ('https URL: ' + $s.Name)
}

if (Test-Summary) { exit 0 } else { exit 1 }
