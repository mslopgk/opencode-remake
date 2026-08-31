# 깃허브 연결 화면. 한 번만 누르면 되는 창이다.
#
# 검증된 github-connect.ps1 의 함수를 그대로 호출한다.

# 로드 시점에 스크립트 폴더를 붙잡아 둔다.
# 함수 안에서 $MyInvocation.MyCommand.Path 는 dot-source 시 null 이다(실측).
$script:CampScriptDir = $PSScriptRoot

function Show-CampGithubConnect {
    $t = Get-CampTheme

    $body = @"
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0">
        <TextBlock x:Name="Guide" Foreground="$($t.Fg)" FontSize="14" TextWrapping="Wrap"
                   LineHeight="24"
                   Text="발표자료를 인터넷 주소로 만들려면 한 번만 연결하면 돼요.&#10;&#10;1. 아래 '연결하기' 를 누르면 검은 창이 열려요.&#10;2. 검은 창에 나오는 8글자를 기억하세요.&#10;3. Enter 를 누르면 인터넷 창이 열려요.&#10;4. 기억한 8글자를 넣고 초록색 단추를 누르면 끝이에요."/>
        <TextBlock x:Name="Note" Foreground="$($t.Sub)" FontSize="12.5" TextWrapping="Wrap"
                   Margin="0,18,0,0"
                   Text="보호자 계정으로 로그인하세요. 잘 모르겠으면 선생님을 불러 주세요."/>
      </StackPanel>
      <StackPanel Grid.Row="1" Margin="0,14,0,0">
        <TextBlock x:Name="Status" Text="" Foreground="$($t.Sub)"
                   FontSize="12.5" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
          <Button x:Name="GoBtn" Content="연결하기" Width="120" Height="34" Margin="0,0,10,0"
                  Background="$($t.Accent)" Foreground="$($t.Bg)" BorderThickness="0"
                  FontWeight="SemiBold" Cursor="Hand"/>
          <Button x:Name="CloseBtn" Content="닫기" Width="96" Height="34"
                  Background="$($t.BgSoft)" Foreground="$($t.Fg)" BorderThickness="0"
                  Cursor="Hand"/>
        </StackPanel>
      </StackPanel>
"@

    $win = New-CampWindow -Title '창의디자인캠프 깃허브 연결' `
        -Heading '인터넷에 올릴 준비' `
        -Sub '한 번만 연결해 두면 언제든 발표자료를 올릴 수 있어요.' `
        -Width 620 -Height 480 -BodyXaml $body

    $guide    = $win.FindName('Guide')
    $note     = $win.FindName('Note')
    $status   = $win.FindName('Status')
    $goBtn    = $win.FindName('GoBtn')
    $closeBtn = $win.FindName('CloseBtn')
    $heading  = $win.FindName('Heading')
    $subText  = $win.FindName('SubText')

    . (Join-Path $script:CampScriptDir 'github-connect.ps1')

    $script:Rc = 1

    # 도구 자체가 없으면 안내만 하고 끝낸다
    if ($null -eq (Get-GhExe)) {
        $heading.Text  = '아직 준비가 안 됐어요'
        $subText.Text  = '설치하기를 먼저 실행해 주세요.'
        $guide.Text    = '인터넷에 올리는 도구가 아직 없어요.'
        $note.Text     = '바탕화면의 "창의디자인캠프 설치" 를 한 번 실행한 뒤에 다시 눌러 주세요.'
        $goBtn.Visibility = 'Collapsed'
        $closeBtn.Add_Click({ $win.Close() })
        $win.ShowDialog() | Out-Null
        return 1
    }

    $showConnected = {
        param($who)
        $heading.Text = '연결됐어요!'
        if ($who) { $subText.Text = $who + ' 계정으로 연결됐어요.' }
        else      { $subText.Text = '이제 발표자료를 인터넷에 올릴 수 있어요.' }
        $guide.Text  = '이제 캠프 앱에서 "올리기" 라고 쓰면 발표자료가 인터넷 주소로 만들어져요.'
        $note.Text   = '이 창은 닫아도 돼요. 다시 연결할 필요는 없어요.'
        $goBtn.Visibility = 'Collapsed'
        $status.Text = ''
        $script:Rc = 0
    }

    if (Test-GithubConnected) { & $showConnected (Get-GithubAccount) }

    $shared = New-CampShared
    $shared.ScriptDir = $script:CampScriptDir

    $work = {
        . "$($Shared.ScriptDir)\github-connect.ps1"
        try { $Shared.Rc = [int](-not (Start-GithubLogin)) }
        catch { $Shared.Rc = 1 }
        $Shared.Done = $true
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        if (-not $shared.Done) { return }
        $timer.Stop()
        Stop-CampWork $script:GuiJob
        if ($shared.Rc -eq 0) { & $showConnected (Get-GithubAccount) }
        else {
            $status.Text = '연결하지 못했어요. 다시 눌러 보거나 선생님을 불러 주세요.'
            $goBtn.IsEnabled = $true
            $goBtn.Content = '다시 연결하기'
        }
    })

    $goBtn.Add_Click({
        $goBtn.IsEnabled = $false
        $status.Text = '검은 창이 열렸어요. 거기 나온 8글자를 넣어 주세요.'
        $shared.Done = $false
        $script:GuiJob = Start-CampWork -Work $work -Shared $shared
        $timer.Start()
    })
    $closeBtn.Add_Click({ $win.Close() })
    $win.Add_Closed({ $timer.Stop(); Stop-CampWork $script:GuiJob })

    $win.ShowDialog() | Out-Null
    return [int]$script:Rc
}
