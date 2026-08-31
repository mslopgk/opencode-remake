# 원클릭 설치 파일을 만든다.
#
# 왜 필요한가: zip 을 주면 학생이 "압축 풀기" 를 해야 한다.
# 초등학교 5학년에게 그건 예외 발생기다. 게다가 zip 창 안에서 설치 파일을
# 바로 두 번 누르면 형제 폴더가 없어서 **조용히 실패**한다. 가장 나쁜 실패다.
#
# 그래서 exe 하나로 만든다. 두 번 누르면 스스로 풀고 설치까지 이어진다.
# 학생 동작은 "두 번 누르기" 한 가지뿐이다.
#
# 어떻게: Windows 에 기본으로 있는 csc.exe 로 작은 WinExe 를 컴파일하고,
# 배포판 zip 을 그 안에 리소스로 박는다. 별도 툴체인을 설치하지 않는다.
# (build-exe.ps1 과 같은 방식이다)

$ErrorActionPreference = 'Stop'

function Get-CscPath {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $csc) { return $null }
    return $csc.FullName
}

# 배포판을 zip 으로 묶는다 (exe 안에 박을 짐)
function New-PayloadZip {
    param([string]$RepoDir, [string]$OutZip)

    $dist = Join-Path $RepoDir 'dist'
    if (-not (Test-Path -LiteralPath $dist -PathType Container)) {
        throw "dist 폴더가 없습니다. build-dist.ps1 을 먼저 실행하세요."
    }
    if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }

    # 이 파일 자신이 dist 안에 있으면 재귀가 된다. 밖에 만든다.
    Write-Host '배포판을 묶고 있습니다...'
    Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $OutZip -CompressionLevel Optimal
    $mb = (Get-Item $OutZip).Length / 1MB
    Write-Host ('  묶음 크기: ' + [math]::Round($mb, 1) + ' MB')
}

$CsSource = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    // 푸는 곳. 사용자 폴더 안이라 관리자 권한이 필요 없다.
    static string DestDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "창의디자인캠프-설치");
    }

    [STAThread]
    static int Main()
    {
        Application.EnableVisualStyles();

        var form = new Form();
        form.Text = "창의디자인캠프 설치";
        form.Width = 460;
        form.Height = 190;
        form.FormBorderStyle = FormBorderStyle.FixedDialog;
        form.MaximizeBox = false;
        form.MinimizeBox = false;
        form.StartPosition = FormStartPosition.CenterScreen;
        form.BackColor = ColorTranslator.FromHtml("#0b2545");

        var title = new Label();
        title.Text = "준비하고 있어요";
        title.ForeColor = ColorTranslator.FromHtml("#5bc0eb");
        title.Font = new Font("맑은 고딕", 15F, FontStyle.Bold);
        title.SetBounds(28, 24, 400, 30);
        form.Controls.Add(title);

        var msg = new Label();
        msg.Text = "잠깐만 기다려 주세요. 곧 설치가 시작돼요.";
        msg.ForeColor = Color.White;
        msg.Font = new Font("맑은 고딕", 10F);
        msg.SetBounds(28, 58, 400, 44);
        form.Controls.Add(msg);

        var bar = new ProgressBar();
        bar.Style = ProgressBarStyle.Marquee;
        bar.MarqueeAnimationSpeed = 30;
        bar.SetBounds(28, 108, 400, 16);
        form.Controls.Add(bar);

        int rc = 1;
        Exception failure = null;

        form.Shown += delegate(object s, EventArgs e)
        {
            var th = new Thread(delegate()
            {
                try { Unpack(); }
                catch (Exception ex) { failure = ex; }

                form.BeginInvoke((MethodInvoker)delegate()
                {
                    if (failure != null)
                    {
                        MessageBox.Show(
                            "준비하지 못했어요. 선생님을 불러 주세요.\n\n" + failure.Message,
                            "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        rc = 1;
                        form.Close();
                        return;
                    }

                    // 설치 화면을 띄우고 이 창은 닫는다
                    string installer = Path.Combine(DestDir(), "창의디자인캠프 설치.exe");
                    try
                    {
                        var psi = new ProcessStartInfo();
                        psi.FileName = installer;
                        psi.WorkingDirectory = DestDir();
                        psi.UseShellExecute = true;
                        Process.Start(psi);
                        rc = 0;
                    }
                    catch (Exception ex2)
                    {
                        MessageBox.Show(
                            "설치를 시작하지 못했어요. 선생님을 불러 주세요.\n\n" + ex2.Message,
                            "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        rc = 1;
                    }
                    form.Close();
                });
            });
            th.IsBackground = true;
            th.Start();
        };

        Application.Run(form);
        return rc;
    }

    static void Unpack()
    {
        string dest = DestDir();

        // 전에 받아서 푼 것이 있으면 지우고 새로 푼다.
        // 반쯤 풀린 상태가 남아 있으면 설치가 이상하게 된다.
        if (Directory.Exists(dest))
        {
            try { Directory.Delete(dest, true); }
            catch { /* 쓰는 중인 파일이 있으면 덮어쓰기로 진행 */ }
        }
        Directory.CreateDirectory(dest);

        var asm = Assembly.GetExecutingAssembly();
        using (Stream src = asm.GetManifestResourceStream("payload.zip"))
        {
            if (src == null) { throw new Exception("안에 든 파일을 찾지 못했습니다."); }

            // 리소스 스트림은 되감기가 안 될 수 있어 임시 파일로 옮긴다
            string tmpZip = Path.Combine(Path.GetTempPath(),
                "camp-payload-" + Guid.NewGuid().ToString("N") + ".zip");
            try
            {
                using (var fs = new FileStream(tmpZip, FileMode.Create, FileAccess.Write))
                {
                    byte[] buf = new byte[1024 * 1024];
                    int n;
                    while ((n = src.Read(buf, 0, buf.Length)) > 0) { fs.Write(buf, 0, n); }
                }
                ZipFile.ExtractToDirectory(tmpZip, dest);
            }
            finally
            {
                try { File.Delete(tmpZip); } catch { }
            }
        }

        // 인터넷에서 받은 표시(차단 플래그)를 떼어 준다.
        // 이걸 안 떼면 설치가 60대에서 전부 막힌다.
        // (orchestrator.ps1 도 다시 한 번 떼지만, 첫 실행 자체가 막히면 안 된다)
        foreach (string f in Directory.GetFiles(dest, "*", SearchOption.AllDirectories))
        {
            try { File.Delete(f + ":Zone.Identifier"); } catch { }
        }
    }
}
'@

function Invoke-BuildInstallerExe([string]$RepoDir) {
    $csc = Get-CscPath
    if ($null -eq $csc) {
        Write-Host 'csc.exe 를 찾을 수 없습니다 (.NET Framework 필요).'
        return 1
    }
    Write-Host ('컴파일러: ' + $csc)

    $icon = Join-Path $RepoDir 'dist\scripts\camp.ico'
    if (-not (Test-Path -LiteralPath $icon -PathType Leaf)) {
        Write-Host '아이콘이 없습니다. make-icon.ps1 을 먼저 실행하세요.'
        return 1
    }

    $work = Join-Path $env:TEMP ('campsfx-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $payload = Join-Path $work 'payload.zip'
        New-PayloadZip -RepoDir $RepoDir -OutZip $payload

        $csFile = Join-Path $work 'Setup.cs'
        [System.IO.File]::WriteAllText($csFile, $CsSource, (New-Object System.Text.UTF8Encoding($true)))

        $outExe = Join-Path $RepoDir 'camp2026-setup.exe'
        if (Test-Path -LiteralPath $outExe) { Remove-Item -LiteralPath $outExe -Force }

        Write-Host '컴파일하고 있습니다 (짐이 커서 1~2분 걸립니다)...'
        # 경로에 공백이 들어가므로 반드시 인용한다
        $args = @(
            '/nologo',
            '/target:winexe',
            '/optimize+',
            ('/win32icon:"' + $icon + '"'),
            '/reference:System.Windows.Forms.dll',
            '/reference:System.Drawing.dll',
            '/reference:System.IO.Compression.dll',
            '/reference:System.IO.Compression.FileSystem.dll',
            ('/resource:"' + $payload + '",payload.zip'),
            ('/out:"' + $outExe + '"'),
            ('"' + $csFile + '"')
        )
        $p = Start-Process -FilePath $csc -ArgumentList $args -PassThru -Wait -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $work 'out.txt') `
                -RedirectStandardError  (Join-Path $work 'err.txt')
        if ($p.ExitCode -ne 0) {
            Write-Host '컴파일 실패:'
            Get-Content -LiteralPath (Join-Path $work 'out.txt') -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { Write-Host ('  ' + $_) }
            Get-Content -LiteralPath (Join-Path $work 'err.txt') -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { Write-Host ('  ' + $_) }
            return 1
        }

        $mb = (Get-Item $outExe).Length / 1MB
        Write-Host ('만들었어요: camp2026-setup.exe (' + [math]::Round($mb, 1) + ' MB)')
        return 0
    }
    finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    exit (Invoke-BuildInstallerExe -RepoDir $repo)
}
