# 캠프 앱 안의 단추를 "이름" 으로 찾아 누른다.
#
# 왜 필요한가 (실측, 2026-09-02):
#   앱은 대화 화면으로 열리지 않는다. 프로젝트·세션 목록 화면으로 열린다.
#   거기에는 글을 쓸 칸이 없다. 학생은 "세션"이 뭔지 모르고, 대본은
#   "화면 맨 아래 길쭉한 칸에 말을 쓰세요" 라고 말한다. 그대로 두면
#   학생 63명이 전부 여기서 막힌다.
#
#   그래서 앱이 열린 뒤 우리가 대신 "내캠페인" 의 새 세션을 눌러 준다.
#   학생이 하는 일은 "캠프 시작 두 번 누르기" 하나로 그대로 남는다.
#
# 왜 좌표를 쓰지 않는가:
#   창 크기·글꼴·앱 버전이 바뀌면 좌표는 전부 어긋난다. 이 앱은 윈도우
#   접근성 트리(UI Automation)에 단추 이름과 자리를 그대로 노출한다(실측).
#   이름으로 찾는 편이 훨씬 오래 버틴다.
#
# 왜 마우스를 쓰지 않는가:
#   학생이 마우스를 잡고 있는 순간 커서를 빼앗으면 클릭이 빗나간다.
#   Invoke 는 단추를 그 자리에서 누른 것과 같게 만든다. 커서는 그대로다.
#
# 이 기능은 전부 "되면 좋은 것" 이다. 실패해도 앱은 열려 있고,
# 학생은 화면의 "새 세션" 을 직접 누르면 된다. 절대 설치·실행을 막지 않는다.

function Initialize-CampUia {
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Get-CampUiElements([IntPtr]$Window) {
    $결과 = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Window)
        if ($null -eq $root) { return @() }
        $전부 = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                              [System.Windows.Automation.Condition]::TrueCondition)
        for ($i = 0; $i -lt $전부.Count; $i++) {
            $e = $전부.Item($i)
            $n = ''; $ct = ''; $r = $null
            try { $n = $e.Current.Name } catch { }
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            try { $ct = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', '' } catch { }
            try { $r = $e.Current.BoundingRectangle } catch { }
            if ($null -eq $r -or $r.Width -le 0 -or $r.Height -le 0) { continue }
            $결과 += @{
                이름 = $n; 종류 = $ct
                X = [int]($r.X + $r.Width / 2); Y = [int]($r.Y + $r.Height / 2)
                넓이 = [int]($r.Width * $r.Height)
            }
        }
    }
    catch { return @() }      # 창이 닫히는 중이면 예외가 난다. 그냥 없는 것으로 본다.
    return $결과
}

# 앱 언어가 한국어가 아닐 수도 있다. 후보를 여러 개 받는다.
function Find-CampUiElement($요소들, [string[]]$이름들, [string]$종류 = '') {
    $쓸것 = @($요소들 | Where-Object { $종류 -eq '' -or $_.종류 -eq $종류 })
    foreach ($이름 in $이름들) {
        $딱맞 = @($쓸것 | Where-Object { $_.이름 -eq $이름 })
        if ($딱맞.Count -ge 1) { return $딱맞[0] }
    }
    foreach ($이름 in $이름들) {
        $포함 = @($쓸것 | Where-Object { $_.이름 -like ('*' + $이름 + '*') } | Sort-Object { $_.넓이 })
        if ($포함.Count -ge 1) { return $포함[0] }
    }
    return $null
}

function Invoke-CampUiElement($요소, [IntPtr]$Window) {
    if ($null -eq $요소) { return $false }
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Window)
        if ($null -eq $root) { return $false }
        $전부 = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                              [System.Windows.Automation.Condition]::TrueCondition)
        for ($i = 0; $i -lt $전부.Count; $i++) {
            $e = $전부.Item($i)
            $n = ''; try { $n = $e.Current.Name } catch { }
            if ($n -ne $요소.이름) { continue }
            $r = $null; try { $r = $e.Current.BoundingRectangle } catch { }
            if ($null -eq $r) { continue }
            $cx = [int]($r.X + $r.Width / 2); $cy = [int]($r.Y + $r.Height / 2)
            if ([math]::Abs($cx - $요소.X) -gt 3 -or [math]::Abs($cy - $요소.Y) -gt 3) { continue }

            try {
                $p = $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if ($null -ne $p) { $p.Invoke(); return $true }
            } catch { }
            try {
                $lp = $e.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
                if ($null -ne $lp) { $lp.DoDefaultAction(); return $true }
            } catch { }
            return $false
        }
    }
    catch { return $false }
    return $false
}

# 프로젝트 한 줄에 붙어 있는 "새 세션" 단추.
#
# 큰 "새 세션" 단추를 누르면 엉뚱한 프로젝트(Default Project)에 세션이
# 생긴다(실측). 그러면 그림과 발표자료가 다른 폴더로 가서 "발표자료 보기"
# 가 빈 화면을 연다. 그래서 원하는 프로젝트 줄과 같은 높이의 단추를 고른다.
function Find-CampProjectNewSession($요소들, [string]$프로젝트) {
    $새세션이름 = @('새 세션', 'New session', 'New Session')
    $줄 = @($요소들 | Where-Object {
        $_.종류 -eq 'Button' -and $_.이름 -like ('*' + $프로젝트 + '*')
    } | Sort-Object { -$_.넓이 })
    if ($줄.Count -eq 0) { return $null }
    $줄Y = $줄[0].Y
    $단추 = @($요소들 | Where-Object {
        $_.종류 -eq 'Button' -and ($새세션이름 -contains $_.이름) -and [math]::Abs($_.Y - $줄Y) -le 12
    } | Sort-Object { -$_.X })
    if ($단추.Count -eq 0) { return $null }
    return $단추[0]
}

# 앱이 열린 뒤, 학생이 바로 말을 쓸 수 있는 상태로 만든다.
# 성공하면 $true. 실패해도 앱은 그대로 열려 있다.
function Open-CampSession {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Window,
        [string]$Project = '내캠페인',
        [int]$WaitSeconds = 30,
        [switch]$Force
    )

    if (-not (Initialize-CampUia)) { return $false }

    $입력이름 = @('프롬프트', 'Prompt')

    # 둘 중 먼저 보이는 쪽을 따른다.
    #   글 쓰는 칸이 보이면  -> 이미 대화 화면이다. 할 일이 없다.
    #   "새 세션" 이 보이면  -> 목록 화면이다. 우리가 눌러 준다.
    #
    # 왜 한 번만 보면 안 되는가 (실측, 2026-09-05):
    #   창이 막 떴을 때는 아직 아무것도 안 그려져 있다. 그 순간 한 번만
    #   보고 넘어가면, 앱이 대화 화면으로 잘 열렸는데도 "못 열었다" 로
    #   판정한다. 그러면 학생에게 필요 없는 안내가 뜨고 창이 안 닫힌다.
    #   실제로 이 기계에서 그렇게 나왔다(입력칸은 있는데 False).
    # Force 면 이미 대화 화면이어도 새 세션을 연다.
    # 설정을 고친 직후에는 옛 대화를 이어 쓰면 바뀐 것이 안 먹을 수 있다.
    $단추 = $null
    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        $요소들 = Get-CampUiElements $Window
        if (-not $Force -and $null -ne (Find-CampUiElement $요소들 $입력이름 'Edit')) { return $true }
        $단추 = Find-CampProjectNewSession $요소들 $Project
        if ($null -ne $단추) { break }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $단추) { return $false }

    if (-not (Invoke-CampUiElement $단추 $Window)) { return $false }

    # 입력칸이 생겼는지 확인한다. 눌렀다고 열린 것은 아니다.
    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        Start-Sleep -Seconds 1
        $요소들 = Get-CampUiElements $Window
        if ($null -ne (Find-CampUiElement $요소들 $입력이름 'Edit')) { return $true }
    }
    return $false
}
