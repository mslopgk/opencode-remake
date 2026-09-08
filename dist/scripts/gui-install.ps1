# 설치 화면.
#
# 검증된 orchestrator.ps1 을 그대로 호출하고, lib-log 의 싱크로 진행 상황을
# 받아 그린다. 설치 로직은 한 줄도 여기서 다시 쓰지 않는다.

# 로드 시점에 스크립트 폴더를 붙잡아 둔다.
# 함수 안에서 $MyInvocation.MyCommand.Path 는 dot-source 시 null 이다(실측).
$script:CampScriptDir = $PSScriptRoot

function Show-CampInstaller([string]$DistDir) {
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
        <ProgressBar x:Name="Bar" Height="4" Minimum="0" Maximum="100" Value="0"
                     Background="$($t.BgSoft)" Foreground="$($t.Accent)"
                     BorderThickness="0"/>
        <TextBlock x:Name="Status" Text="시작할게요" Foreground="$($t.Sub)"
                   FontSize="12.5" Margin="0,10,0,0" TextWrapping="Wrap"/>
        <Button x:Name="CloseBtn" Content="닫기" Width="96" Height="34"
                HorizontalAlignment="Right" Margin="0,14,0,0" Visibility="Collapsed"
                Background="$($t.Accent)" Foreground="$($t.Bg)" BorderThickness="0"
                FontWeight="SemiBold" Cursor="Hand"/>
      </StackPanel>
"@

    $win = New-CampWindow -Title '창의디자인캠프 설치' `
        -Heading '준비하고 있어요' `
        -Sub '5분에서 10분쯤 걸려요. 창을 닫지 말고 기다려 주세요.' `
        -Width 640 -Height 560 -BodyXaml $body

    $stepsHost = $win.FindName('Steps')
    $bar       = $win.FindName('Bar')
    $status    = $win.FindName('Status')
    $closeBtn  = $win.FindName('CloseBtn')
    $heading   = $win.FindName('Heading')
    $subText   = $win.FindName('SubText')

    # 화면에 보여줄 단계. orchestrator 가 내보내는 문구와 앞부분이 맞아야 한다.
    $titles = @(
        '컴퓨터 확인',
        '파일 차단 풀기',
        '필요한 부품 설치',
        '만들기 도구 넣기',
        '캠프 설정 넣기',
        '연습 폴더 만들기',
        '잘 됐는지 확인'
    )
    $rows = New-CampStepList -Panel $stepsHost -Titles $titles

    # orchestrator 의 메시지를 위 단계에 매핑한다
    $map = @(
        @{ Key = '컴퓨터를';    Step = '컴퓨터 확인' },
        @{ Key = '파일 차단';   Step = '파일 차단 풀기' },
        @{ Key = '설치하고 있어요'; Step = '필요한 부품 설치' },
        @{ Key = '이미 있어요'; Step = '필요한 부품 설치' },
        @{ Key = '만들기 도구'; Step = '만들기 도구 넣기' },
        @{ Key = '캠프 설정';   Step = '캠프 설정 넣기' },
        @{ Key = '연습 폴더';   Step = '연습 폴더 만들기' },
        @{ Key = '확인할게요';  Step = '잘 됐는지 확인' },
        @{ Key = '확인 중';     Step = '잘 됐는지 확인' }
    )

    $shared = New-CampShared
    $queue  = $shared.Queue

    $scriptDir = $script:CampScriptDir
    $work = {
        . "$($Shared.ScriptDir)\lib-log.ps1"
        . "$($Shared.ScriptDir)\lib-appstate.ps1"
        . "$($Shared.ScriptDir)\lib-team.ps1"
        . "$($Shared.ScriptDir)\selfcheck.ps1"
        . "$($Shared.ScriptDir)\lib-shellfix.ps1"
        . "$($Shared.ScriptDir)\orchestrator.ps1"

        $q = $Shared.Queue
        Set-CampLogSink { param($level, $msg) $q.Enqueue(@{ level = $level; msg = $msg }) }
        Start-CampLog (Join-Path $env:USERPROFILE '창의디자인캠프\설치기록.txt')
        try {
            $Shared.Rc = Invoke-Install -DistDir $Shared.DistDir
        }
        catch {
            $q.Enqueue(@{ level = 'fail'; msg = ('예상 못한 문제가 생겼어요: ' + $_.Exception.Message) })
            $Shared.Rc = 1
        }
        Stop-CampLog
        Clear-CampLogSink
        $Shared.Done = $true
    }
    $shared.ScriptDir = $scriptDir
    $shared.DistDir = $DistDir

    $job = $null
    $current = -1   # 지금 진행 중인 단계의 인덱스

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $msg = [string]$item.msg
            $lvl = [string]$item.level

            $status.Text = $msg

            # 어느 단계 이야기인지 찾는다.
            #
            # 완료 문구가 시작 문구와 달라서(예: "파일 차단을 풀고 있어요" →
            # "차단을 풀었어요") 문구 매칭만으로는 끝난 단계가 계속 진행 중으로
            # 남는다. 단계는 순서대로 흐르므로 인덱스로 처리한다:
            # 어떤 단계가 시작되면 그보다 앞선 단계는 모두 끝난 것이다.
            foreach ($m in $map) {
                if ($msg -like ('*' + $m.Key + '*')) {
                    $idx = $titles.IndexOf($m.Step)
                    if ($idx -lt 0) { break }
                    if ($idx -ge $current) {
                        for ($i = 0; $i -lt $idx; $i++) {
                            Set-CampStepState -Row $rows[$titles[$i]] -State 'done'
                        }
                        $current = $idx
                        if ($lvl -eq 'fail') { Set-CampStepState -Row $rows[$m.Step] -State 'fail' }
                        elseif ($lvl -eq 'ok') { Set-CampStepState -Row $rows[$m.Step] -State 'done' }
                        else { Set-CampStepState -Row $rows[$m.Step] -State 'running' }
                    }
                    break
                }
            }

            $bar.Value = [math]::Min(100, [int](100 * ($current + 1) / $titles.Count))
        }

        if ($shared.Done) {
            $timer.Stop()
            $bar.Value = 100
            $t2 = Get-CampTheme
            if ($shared.Rc -eq 0) {
                foreach ($k in $titles) { Set-CampStepState -Row $rows[$k] -State 'done' }
                $heading.Text = '준비 끝!'
                $subText.Text = '캠프 당일 아침에 "캠프 시작" 을 눌러 주세요.'
                $status.Text = ''
                $bar.Foreground = $t2.Good
            }
            else {
                $heading.Text = '조금 더 손이 필요해요'
                $subText.Text = '여기서 그만해도 괜찮아요. 캠프 첫날 아침에 5분이면 고쳐 드려요.'
                $status.Text = '기록 파일: ' + (Join-Path $env:USERPROFILE '창의디자인캠프\설치기록.txt')
                $bar.Foreground = $t2.Bad
            }
            $closeBtn.Visibility = 'Visible'
        }
    })

    $closeBtn.Add_Click({ $win.Close() })

    $win.Add_ContentRendered({
        $script:GuiJob = Start-CampWork -Work $work -Shared $shared
        $timer.Start()
    })
    $win.Add_Closed({
        $timer.Stop()
        Stop-CampWork $script:GuiJob
    })

    $win.ShowDialog() | Out-Null
    if ($null -eq $shared.Rc) { return 1 }
    return [int]$shared.Rc
}
