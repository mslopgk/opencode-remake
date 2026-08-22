# 당일 아침 런처 화면.
#
# 콘솔 Read-Host 대신 입력 폼을 쓴다. 보기에도 낫고, 파이프 입력을 못 읽던
# Read-Host 의 한계도 사라진다(자동 검증이 가능해진다).
#
# 학생 이름은 묻지 않는다. 조 번호와 팀 이름만 받는다.

# 로드 시점에 스크립트 폴더를 붙잡아 둔다.
# 함수 안에서 $MyInvocation.MyCommand.Path 는 dot-source 시 null 이다(실측).
$script:CampScriptDir = $PSScriptRoot

function Show-CampLauncher([string]$TemplateDir) {
    $t = Get-CampTheme

    $body = @"
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <TextBlock Text="우리는 몇 조예요?" Foreground="$($t.Sub)" FontSize="12.5"/>
        <TextBox x:Name="NumBox" Height="38" Margin="0,6,0,0" MaxLength="2"
                 Background="$($t.BgSoft)" Foreground="$($t.Fg)" BorderThickness="0"
                 FontSize="18" Padding="10,0,0,0" VerticalContentAlignment="Center"
                 CaretBrush="$($t.Accent)"/>
      </StackPanel>

      <StackPanel Grid.Row="1" Margin="0,16,0,0">
        <TextBlock Text="우리 팀 이름은 뭐예요?" Foreground="$($t.Sub)" FontSize="12.5"/>
        <TextBox x:Name="NameBox" Height="38" Margin="0,6,0,0" MaxLength="20"
                 Background="$($t.BgSoft)" Foreground="$($t.Fg)" BorderThickness="0"
                 FontSize="18" Padding="10,0,0,0" VerticalContentAlignment="Center"
                 CaretBrush="$($t.Accent)"/>
      </StackPanel>

      <StackPanel Grid.Row="2" Margin="0,18,0,0">
        <TextBlock x:Name="Hint" Text="조 번호는 1부터 15까지예요." Foreground="$($t.Sub)"
                   FontSize="12" Opacity="0.8" TextWrapping="Wrap"/>
        <StackPanel x:Name="Steps" Margin="0,14,0,0"/>
      </StackPanel>

      <Button x:Name="GoBtn" Grid.Row="3" Content="시작하기" Width="132" Height="40"
              HorizontalAlignment="Right" Margin="0,10,0,0"
              Background="$($t.Accent)" Foreground="$($t.Bg)" BorderThickness="0"
              FontSize="15" FontWeight="SemiBold" Cursor="Hand"/>
"@

    $win = New-CampWindow -Title '창의디자인캠프 시작' `
        -Heading '우리 팀을 만들어요' `
        -Sub '조 번호와 팀 이름만 알려 주세요.' `
        -Width 560 -Height 470 -BodyXaml $body

    $numBox  = $win.FindName('NumBox')
    $nameBox = $win.FindName('NameBox')
    $hint    = $win.FindName('Hint')
    $goBtn   = $win.FindName('GoBtn')
    $steps   = $win.FindName('Steps')
    $heading = $win.FindName('Heading')
    $subText = $win.FindName('SubText')

    $shared = New-CampShared
    $shared.ScriptDir = $script:CampScriptDir
    $shared.TemplateDir = $TemplateDir

    $goBtn.Add_Click({
        $t2 = Get-CampTheme
        $numText = ($numBox.Text -replace '[^0-9]', '')
        $teamName = $nameBox.Text.Trim()

        $num = 0
        if (-not [int]::TryParse($numText, [ref]$num) -or $num -lt 1 -or $num -gt 15) {
            $hint.Text = '조 번호는 1부터 15까지 숫자로 써 주세요.'
            $hint.Foreground = $t2.Bad
            $hint.Opacity = 1.0
            return
        }
        if ([string]::IsNullOrWhiteSpace($teamName)) {
            $hint.Text = '팀 이름을 알려 주세요.'
            $hint.Foreground = $t2.Bad
            $hint.Opacity = 1.0
            return
        }
        foreach ($ch in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) {
            if ($teamName.Contains($ch)) {
                $hint.Text = '팀 이름에는 특수문자를 쓸 수 없어요.'
                $hint.Foreground = $t2.Bad
                $hint.Opacity = 1.0
                return
            }
        }

        $goBtn.IsEnabled = $false
        $numBox.IsEnabled = $false
        $nameBox.IsEnabled = $false
        $hint.Text = ''

        $shared.Number = $num
        $shared.Name = $teamName

        $rows = New-CampStepList -Panel $steps -Titles @('팀 폴더 만들기', '앱에 등록하기', '앱 열기')
        $script:LauncherRows = $rows

        $work = {
            . "$($Shared.ScriptDir)\lib-log.ps1"
            . "$($Shared.ScriptDir)\lib-appstate.ps1"
            . "$($Shared.ScriptDir)\lib-team.ps1"
            . "$($Shared.ScriptDir)\launcher.ps1"
            $q = $Shared.Queue
            Set-CampLogSink { param($level, $msg) $q.Enqueue(@{ level = $level; msg = $msg }) }
            $parent = Join-Path $env:USERPROFILE '창의디자인캠프'
            Start-CampLog (Join-Path $parent '시작기록.txt')
            try {
                $r = Invoke-Launcher -Number $Shared.Number -Name $Shared.Name `
                        -Parent $parent -TemplateDir $Shared.TemplateDir
                $Shared.Rc = 0
                if (-not $r.Ok) { $Shared.Rc = 1 }
                $Shared.Dir = $r.Dir
            }
            catch {
                $q.Enqueue(@{ level = 'fail'; msg = ('문제가 생겼어요: ' + $_.Exception.Message) })
                $Shared.Rc = 1
            }
            Stop-CampLog
            Clear-CampLogSink
            $Shared.Done = $true
        }

        $queue = $shared.Queue
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(120)
        $timer.Add_Tick({
            while ($queue.Count -gt 0) {
                $item = $queue.Dequeue()
                $msg = [string]$item.msg
                $lvl = [string]$item.level
                if ($msg -like '*팀 폴더*') {
                    $st = 'done'
                    if ($lvl -eq 'fail') { $st = 'fail' }
                    Set-CampStepState -Row $script:LauncherRows['팀 폴더 만들기'] -State $st
                }
                elseif ($msg -like '*등록*') {
                    $st = 'skip'
                    if ($lvl -eq 'ok') { $st = 'done' }
                    Set-CampStepState -Row $script:LauncherRows['앱에 등록하기'] -State $st
                }
                elseif ($msg -like '*앱을 열*' -or $msg -like '*앱이 열*') {
                    Set-CampStepState -Row $script:LauncherRows['앱 열기'] -State 'done'
                }
            }
            if ($shared.Done) {
                $timer.Stop()
                $t3 = Get-CampTheme
                if ($shared.Rc -eq 0) {
                    $heading.Text = '시작해요!'
                    $subText.Text = '앱이 열리면 /시작 이라고 써 보세요.'
                    $win.Dispatcher.InvokeAsync({ Start-Sleep -Milliseconds 1200; $win.Close() }) | Out-Null
                }
                else {
                    $heading.Text = '문제가 생겼어요'
                    $subText.Text = '선생님을 불러 주세요.'
                    $goBtn.Content = '닫기'
                    $goBtn.IsEnabled = $true
                }
            }
        })

        $script:GuiJob = Start-CampWork -Work $work -Shared $shared
        $timer.Start()
    })

    $numBox.Add_KeyDown({ if ($_.Key -eq 'Return') { $nameBox.Focus() | Out-Null } })
    $nameBox.Add_KeyDown({ if ($_.Key -eq 'Return') { $goBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } })
    $win.Add_ContentRendered({ $numBox.Focus() | Out-Null })
    $win.Add_Closed({ Stop-CampWork $script:GuiJob })

    $win.ShowDialog() | Out-Null
    if ($null -eq $shared.Rc) { return 1 }
    return [int]$shared.Rc
}
