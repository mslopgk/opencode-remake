# 창의디자인캠프 GUI 공용 부품 (WPF).
#
# 색은 학생 발표자료의 기본 테마(ocean)와 같은 계열을 쓴다.
# 설치 화면과 학생 결과물이 같은 세계에 있어 보이게 하려는 의도다.
#   --bg #0b2545 / --accent #5bc0eb / --sub #a8dadc  (template/index.html)
#
# 긴 작업은 별도 런스페이스에서 돌리고 UI 스레드는 큐를 폴링해 그린다.
# 같은 스레드에서 돌리면 창이 얼어붙는다.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:CampTheme = @{
    Bg      = '#0B2545'
    BgSoft  = '#123055'
    Fg      = '#FFFFFF'
    Sub     = '#A8DADC'
    Accent  = '#5BC0EB'
    Good    = '#7CD8A4'
    Bad     = '#FF8A7A'
    Warn    = '#FFD9A0'
    Font    = 'Malgun Gothic'
}

function Get-CampTheme { return $script:CampTheme }

# ── 창 껍데기 ────────────────────────────────────────────────────────────────
# XAML 로 만든다. 코드로 한 컨트롤씩 붙이는 것보다 레이아웃이 안정적이다.
function New-CampWindow {
    param(
        [string]$Title,
        [string]$Heading,
        [string]$Sub,
        [int]$Width = 620,
        [int]$Height = 520,
        [string]$BodyXaml
    )
    $t = $script:CampTheme
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Width="$Width" Height="$Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="$($t.Bg)" FontFamily="$($t.Font)" FontSize="14">
  <Grid Margin="28,24,28,22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,18">
      <TextBlock Text="창의디자인캠프" Foreground="$($t.Accent)" FontSize="12"
                 FontWeight="SemiBold" Opacity="0.9"/>
      <TextBlock x:Name="Heading" Text="$Heading" Foreground="$($t.Fg)"
                 FontSize="26" FontWeight="Bold" Margin="0,6,0,0" TextWrapping="Wrap"/>
      <TextBlock x:Name="SubText" Text="$Sub" Foreground="$($t.Sub)" FontSize="13"
                 Margin="0,6,0,0" TextWrapping="Wrap"/>
      <Border Height="1" Background="$($t.BgSoft)" Margin="0,16,0,0"/>
    </StackPanel>
    <Grid Grid.Row="1">
$BodyXaml
    </Grid>
  </Grid>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

# ── 단계 목록 ────────────────────────────────────────────────────────────────
# 상태를 글자로만 쓰지 않고 표식으로도 보여준다. 한눈에 읽혀야 한다.
function New-CampStepList {
    param([System.Windows.Controls.Panel]$Panel, [string[]]$Titles)
    $t = $script:CampTheme
    $rows = @{}
    foreach ($title in $Titles) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,9'
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = 26
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $row.ColumnDefinitions.Add($c1)
        $row.ColumnDefinitions.Add($c2)

        $mark = New-Object System.Windows.Controls.TextBlock
        $mark.Text = '·'
        $mark.FontSize = 16
        $mark.Foreground = $t.BgSoft
        $mark.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($mark, 0)

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $title
        $label.Foreground = $t.Sub
        $label.Opacity = 0.55
        $label.TextWrapping = 'Wrap'
        $label.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($label, 1)

        $row.Children.Add($mark) | Out-Null
        $row.Children.Add($label) | Out-Null
        $Panel.Children.Add($row) | Out-Null

        $rows[$title] = @{ Mark = $mark; Label = $label }
    }
    return $rows
}

function Set-CampStepState {
    param($Row, [string]$State)
    if ($null -eq $Row) { return }
    $t = $script:CampTheme
    if ($State -eq 'running') {
        $Row.Mark.Text = '→'
        $Row.Mark.Foreground = $t.Accent
        $Row.Label.Foreground = $t.Fg
        $Row.Label.Opacity = 1.0
    }
    elseif ($State -eq 'done') {
        $Row.Mark.Text = '✓'
        $Row.Mark.Foreground = $t.Good
        $Row.Label.Foreground = $t.Sub
        $Row.Label.Opacity = 1.0
    }
    elseif ($State -eq 'skip') {
        $Row.Mark.Text = '✓'
        $Row.Mark.Foreground = $t.Sub
        $Row.Label.Foreground = $t.Sub
        $Row.Label.Opacity = 0.75
    }
    elseif ($State -eq 'fail') {
        $Row.Mark.Text = '✕'
        $Row.Mark.Foreground = $t.Bad
        $Row.Label.Foreground = $t.Bad
        $Row.Label.Opacity = 1.0
    }
}

# ── 백그라운드 작업 ──────────────────────────────────────────────────────────
# 긴 작업을 런스페이스에서 돌리고, UI 는 큐를 폴링한다.
function Start-CampWork {
    param(
        [scriptblock]$Work,        # param($queue) 를 받는다. $queue.Enqueue(@{level=..;msg=..})
        [hashtable]$Shared         # 결과를 담아 돌려줄 동기화 해시테이블
    )
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Shared', $Shared)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($Work) | Out-Null
    $handle = $ps.BeginInvoke()

    return @{ Ps = $ps; Rs = $rs; Handle = $handle }
}

function Stop-CampWork($Job) {
    if ($null -eq $Job) { return }
    try { $Job.Ps.EndInvoke($Job.Handle) | Out-Null } catch { }
    try { $Job.Ps.Dispose() } catch { }
    try { $Job.Rs.Close(); $Job.Rs.Dispose() } catch { }
}

function New-CampQueue {
    # 쉼표가 반드시 필요하다. PowerShell 은 함수가 반환한 컬렉션을 파이프라인에서
    # 풀어헤치므로(unroll), 빈 Queue 를 그냥 return 하면 아무것도 없이 풀려
    # 호출한 쪽에서 $null 을 받는다. 실측으로 겪은 함정이다.
    $q = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    return ,$q
}

function New-CampShared {
    return [hashtable]::Synchronized(@{ Done = $false; Rc = $null; Queue = (New-CampQueue) })
}
