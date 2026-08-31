# 발표자료 보기. 바탕화면 아이콘 하나로 끝낸다.
#
# 왜 따로 만드나: 초등학교 5학년에게 슬래시(/) 키를 찾게 하는 것이
# 이 캠프에서 가장 큰 실패 지점이었다. 물음표가 나오고, 한/영 상태를
# 모르고, 손이 안 따라간다. 발표자료 보기는 하루에 수십 번 하는 일이라
# 여기에 벽을 두면 안 된다.
#
# 아이들이 이미 배운 동작(바탕화면 아이콘 두 번 누르기)을 그대로 쓴다.
# 키보드도, 도우미도, 모델 판단도 끼지 않는다. 실패할 구석이 없다.

$script:CampScriptDir = $PSScriptRoot

# 학생의 팀 폴더를 찾는다.
# 1순위: 앱에 등록된 프로젝트 (런처가 등록해 둔다)
# 2순위: ~/창의디자인캠프 안에서 가장 최근에 손댄 팀 폴더
function Get-CampTeamDir {
    try {
        $projects = @(Get-RegisteredProjects)
        foreach ($p in $projects) {
            if ((Test-Path -LiteralPath $p -PathType Container) -and
                (Test-Path -LiteralPath (Join-Path $p 'index.html') -PathType Leaf)) {
                return $p
            }
        }
    } catch { }

    # 바탕화면과 옛 위치를 둘 다 본다
    $roots = @()
    try { $roots += [Environment]::GetFolderPath('Desktop') } catch { }
    $roots += (Join-Path $env:USERPROFILE 'Desktop')
    $roots += (Join-Path $env:USERPROFILE '창의디자인캠프')

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $cand = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'index.html') } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $cand) { return $cand.FullName }
    }
    return $null
}

# 화면 없이 쓰는 진입점. 성공하면 0.
function Show-CampSlides {
    $dir = Get-CampTeamDir
    if ($null -eq $dir) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "아직 발표자료가 없어요.`n`n먼저 바탕화면의 '캠프 시작' 을 눌러 주세요.",
            '창의디자인캠프', 'OK', 'Information') | Out-Null
        return 1
    }

    $html = Join-Path $dir 'index.html'
    try {
        # 기본 브라우저로 연다. 학생에게 경로를 보여주지 않는다.
        Start-Process -FilePath $html | Out-Null
        return 0
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "발표자료를 열지 못했어요.`n선생님을 불러 주세요.",
            '창의디자인캠프', 'OK', 'Warning') | Out-Null
        return 1
    }
}
