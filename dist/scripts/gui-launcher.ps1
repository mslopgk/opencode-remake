# 당일 아침 런처 화면.
#
# 아무것도 묻지 않는다. 열자마자 준비를 시작하고 앱을 띄운다.
#
# 왜 입력을 없앴나: 초등학교 5학년에게 시작하자마자 칸 두 개를 채우게 하면
# 거기서 막힌다. "칸을 먼저 눌러야 글자가 써진다" 를 따로 가르쳐야 하고,
# 팀 이름 칸에 실명을 적는 사고도 난다.
# 조 번호와 팀 이름은 도우미가 대화하다가 물어서 우리팀.md 에 적는다.
# 학생은 어차피 채팅 칸에 글 쓰는 법을 배우므로 새로 배울 것이 없다.

# 로드 시점에 스크립트 폴더를 붙잡아 둔다.
# 함수 안에서 $MyInvocation.MyCommand.Path 는 dot-source 시 null 이다(실측).
$script:CampScriptDir = $PSScriptRoot

function Show-CampLauncher([string]$TemplateDir) {
    $t = Get-CampTheme

    $body = @"
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <StackPanel x:Name="Steps"/>
        <TextBlock x:Name="Hint" Text="" Foreground="$($t.Sub)"
                   FontSize="12.5" Opacity="0.9" TextWrapping="Wrap" Margin="0,14,0,0"/>
      </StackPanel>

      <Button x:Name="CloseBtn" Grid.Row="1" Content="닫기" Width="110" Height="38"
              HorizontalAlignment="Right" Margin="0,10,0,0" Visibility="Collapsed"
              Background="$($t.Accent)" Foreground="$($t.Bg)" BorderThickness="0"
              FontSize="15" FontWeight="SemiBold" Cursor="Hand"/>
"@

    $win = New-CampWindow -Title '창의디자인캠프 시작' `
        -Heading '준비하고 있어요' `
        -Sub '잠깐만 기다려 주세요. 곧 시작해요.' `
        -Width 560 -Height 400 -BodyXaml $body

    $hint     = $win.FindName('Hint')
    $steps    = $win.FindName('Steps')
    $closeBtn = $win.FindName('CloseBtn')
    $heading  = $win.FindName('Heading')
    $subText  = $win.FindName('SubText')

    $shared = New-CampShared
    $shared.ScriptDir = $script:CampScriptDir
    $shared.TemplateDir = $TemplateDir

    $rows = New-CampStepList -Panel $steps -Titles @('작업 폴더 준비', '앱에 등록하기', '앱 열기')
    $script:LauncherRows = $rows
    $script:LauncherNotes = @()

    $work = {
        . "$($Shared.ScriptDir)\lib-log.ps1"
        . "$($Shared.ScriptDir)\lib-appstate.ps1"
        . "$($Shared.ScriptDir)\lib-team.ps1"
        . "$($Shared.ScriptDir)\lib-uia.ps1"
        . "$($Shared.ScriptDir)\launcher.ps1"
        $q = $Shared.Queue
        Set-CampLogSink { param($level, $msg) $q.Enqueue(@{ level = $level; msg = $msg }) }
        $logDir = Join-Path $env:USERPROFILE '창의디자인캠프'
        Start-CampLog (Join-Path $logDir '시작기록.txt')
        try {
            # Parent 를 비워 두면 바탕화면에 만든다
            $r = Invoke-Launcher -Parent '' -TemplateDir $Shared.TemplateDir
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
            if ($msg -like '*작업 폴더*') {
                $st = 'done'
                if ($lvl -eq 'fail') { $st = 'fail' }
                Set-CampStepState -Row $script:LauncherRows['작업 폴더 준비'] -State $st
            }
            elseif ($msg -like '*등록*') {
                $st = 'skip'
                if ($lvl -eq 'ok') { $st = 'done' }
                Set-CampStepState -Row $script:LauncherRows['앱에 등록하기'] -State $st
            }
            elseif ($msg -like '*앱을 열*' -or $msg -like '*앱이 열*') {
                # 실측 사고: 진행 문구('앱을 열고 있어요')와 실패 문구
                # ('앱이 열리지 않았어요')가 같은 와일드카드에 걸려서
                # 실패해도 초록 체크가 켜졌다. 등급으로 갈라야 한다.
                $st = 'running'
                if ($lvl -eq 'ok')   { $st = 'done' }
                if ($lvl -eq 'fail') { $st = 'fail' }
                Set-CampStepState -Row $script:LauncherRows['앱 열기'] -State $st
            }
            elseif ($lvl -eq 'note' -or $lvl -eq 'fail') {
                # 안내·실패 문구가 창에 한 줄도 안 나오던 문제.
                # 콘솔에만 찍히고 학생이 쓰는 .exe 화면에서는 사라졌다.
                $script:LauncherNotes += $msg
            }
        }
        if ($shared.Done) {
            $timer.Stop()
            $안내 = ($script:LauncherNotes -join '  ')
            if ($shared.Rc -eq 0) {
                $heading.Text = '시작해요!'
                $subText.Text = '도우미에게 그냥 말을 걸어 보세요.'
                $hint.Text = $안내
                if ([string]::IsNullOrWhiteSpace($안내)) {
                    # 할 말이 없을 때만 스스로 닫는다. 안내가 있으면
                    # 학생이 읽을 시간을 줘야 한다 (실측: 창이 1.2초 만에
                    # 닫혀서 "새 세션을 누르세요" 안내가 통째로 사라졌다).
                    $win.Dispatcher.InvokeAsync({ Start-Sleep -Milliseconds 1200; $win.Close() }) | Out-Null
                }
                else {
                    $closeBtn.Visibility = 'Visible'
                }
            }
            else {
                $heading.Text = '앱이 열리지 않았어요'
                $subText.Text = '창을 닫고 "캠프 시작" 을 한 번 더 눌러 보세요.'
                $hint.Text = $안내
                $closeBtn.Visibility = 'Visible'
            }
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
