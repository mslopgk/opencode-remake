# 점검 화면. 여섯 항목이 실시간으로 켜진다.
#
# 검증된 selfcheck.ps1 의 Invoke-SelfCheck 를 그대로 호출한다.

# 로드 시점에 스크립트 폴더를 붙잡아 둔다.
# 함수 안에서 $MyInvocation.MyCommand.Path 는 dot-source 시 null 이다(실측).
$script:CampScriptDir = $PSScriptRoot

function Show-CampChecker {
    $t = Get-CampTheme

    $body = @"
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="Steps"/>
      </ScrollViewer>
      <StackPanel Grid.Row="1" Margin="0,14,0,0">
        <TextBlock x:Name="Status" Text="확인을 시작할게요" Foreground="$($t.Sub)"
                   FontSize="12.5" TextWrapping="Wrap"/>
        <Button x:Name="CloseBtn" Content="닫기" Width="96" Height="34"
                HorizontalAlignment="Right" Margin="0,14,0,0" Visibility="Collapsed"
                Background="$($t.Accent)" Foreground="$($t.Bg)" BorderThickness="0"
                FontWeight="SemiBold" Cursor="Hand"/>
      </StackPanel>
"@

    $win = New-CampWindow -Title '창의디자인캠프 점검' `
        -Heading '잘 됐는지 확인해요' `
        -Sub '여섯 가지를 하나씩 확인합니다. 1분쯤 걸려요.' `
        -Width 600 -Height 460 -BodyXaml $body

    $stepsHost = $win.FindName('Steps')
    $status    = $win.FindName('Status')
    $closeBtn  = $win.FindName('CloseBtn')
    $heading   = $win.FindName('Heading')
    $subText   = $win.FindName('SubText')

    $titles = @('도구가 깔렸는지', '캠프 설정이 들어갔는지', '만들기 도구가 있는지',
                'AI 도우미가 연결되는지', '그림 만들기가 연결되는지',
                '인터넷에 올리는 도구가 있는지')
    $rows = New-CampStepList -Panel $stepsHost -Titles $titles

    $map = @(
        @{ Key = '도구가 깔렸';   Step = '도구가 깔렸는지' },
        @{ Key = '캠프 설정';     Step = '캠프 설정이 들어갔는지' },
        @{ Key = '만들기 도구';   Step = '만들기 도구가 있는지' },
        @{ Key = 'AI 도우미';     Step = 'AI 도우미가 연결되는지' },
        @{ Key = '그림 만들기';   Step = '그림 만들기가 연결되는지' },
        @{ Key = '인터넷에 올리는'; Step = '인터넷에 올리는 도구가 있는지' }
    )

    $shared = New-CampShared
    $queue = $shared.Queue
    $shared.ScriptDir = $script:CampScriptDir

    $work = {
        . "$($Shared.ScriptDir)\lib-log.ps1"
        . "$($Shared.ScriptDir)\selfcheck.ps1"
        $q = $Shared.Queue
        Set-CampLogSink { param($level, $msg) $q.Enqueue(@{ level = $level; msg = $msg }) }
        Start-CampLog (Join-Path $env:USERPROFILE '창의디자인캠프\점검기록.txt')
        try { $Shared.Rc = Invoke-SelfCheck }
        catch {
            $q.Enqueue(@{ level = 'fail'; msg = ('확인 중 문제가 생겼어요: ' + $_.Exception.Message) })
            $Shared.Rc = 1
        }
        Stop-CampLog
        Clear-CampLogSink
        $Shared.Done = $true
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $msg = [string]$item.msg
            $lvl = [string]$item.level
            $status.Text = $msg
            foreach ($m in $map) {
                if ($msg -like ('*' + $m.Key + '*')) {
                    if ($lvl -eq 'ok')      { Set-CampStepState -Row $rows[$m.Step] -State 'done' }
                    elseif ($lvl -eq 'fail') { Set-CampStepState -Row $rows[$m.Step] -State 'fail' }
                    else                     { Set-CampStepState -Row $rows[$m.Step] -State 'running' }
                    break
                }
            }
        }
        if ($shared.Done) {
            $timer.Stop()
            $t2 = Get-CampTheme
            if ($shared.Rc -eq 0) {
                $heading.Text = '다 좋아요!'
                $subText.Text = '"캠프 시작" 을 눌러서 시작하면 돼요.'
                $status.Text = ''
            }
            else {
                $heading.Text = '안 되는 게 있어요'
                $subText.Text = '선생님을 불러 주세요.'
            }
            $closeBtn.Visibility = 'Visible'
        }
    })

    $closeBtn.Add_Click({ $win.Close() })
    $win.Add_ContentRendered({
        $script:GuiJob = Start-CampWork -Work $work -Shared $shared
        $timer.Start()
    })
    $win.Add_Closed({ $timer.Stop(); Stop-CampWork $script:GuiJob })

    $win.ShowDialog() | Out-Null
    if ($null -eq $shared.Rc) { return 1 }
    return [int]$shared.Rc
}
