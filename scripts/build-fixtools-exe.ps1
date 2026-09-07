# "도구 고치기.exe" 를 만든다.
#
# 왜 필요한가 (실측, 2026-09-05 현장):
#   설치를 이미 끝낸 학생 노트북에는 옛 도구가 들어 있다. 오늘 오후에
#   영상 만들기 버그(durationSeconds 를 문자열로 보내 400)를 고쳤는데,
#   그 고침이 학생 노트북까지 가지 않는다. 도구는 설치 파일 안에 들어 있고
#   설치 파일은 375MB 라, 그것 하나 때문에 60명이 다시 받게 할 수는 없다.
#
#   그래서 도구 여섯 개(60KB)만 받아 갈아끼우는 작은 파일을 따로 만든다.
#   학생이 하는 일은 여전히 "두 번 누르기" 하나다.
#
# 관리자 권한이 필요 없다. 도구는 %LOCALAPPDATA% 안에 있다.

$ErrorActionPreference = 'Stop'

function Get-CscPath {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $csc) { return $null }
    return $csc.FullName
}

$CsSource = @'
using System;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Windows.Forms;

static class Program
{
    static string ToolsDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs\\camp-tools");
    }

    // 이미 만들어진 팀 폴더에서 예시 슬라이드를 지운다.
    //
    // 왜 (2026-09-05 현장): 새 규칙을 넣어도 도우미가 옛 발표자료를 되돌아가
    // 고치지는 않는다. 예시 일곱 장이 그대로 남아 발표에 끼어 나온다.
    // 사람이 지우게 하지 말고 도구가 지운다. 학생이 손댄 장은 글이 달라져서
    // 아래 표시와 안 맞으므로 건드리지 않는다.
    static readonly string[] 예시표시 = new string[] {
        "어떤 문제를 보고 안타까웠는지 적어요",
        "우리가 어떻게 하면 ○○할 수 있을까?",
        "무엇을 하는 캠페인인지",
        "여기에 우리가 만든 그림이 들어갑니다",
        "오늘부터 할 수 있는 일",
        "들어 주셔서 고맙습니다!"
    };

    static int 예시장지우기()
    {
        int 고친파일 = 0;
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var 뿌리들 = new System.Collections.Generic.List<string>();
        뿌리들.Add(Path.Combine(home, "창의디자인캠프"));
        뿌리들.Add(Path.Combine(home, "Desktop"));
        뿌리들.Add(Path.Combine(home, "OneDrive", "바탕 화면"));
        뿌리들.Add(Path.Combine(home, "바탕 화면"));

        foreach (string 뿌리 in 뿌리들)
        {
            if (!Directory.Exists(뿌리)) { continue; }
            string[] 파일들;
            try { 파일들 = Directory.GetFiles(뿌리, "index.html", SearchOption.AllDirectories); }
            catch { continue; }

            foreach (string f in 파일들)
            {
                try
                {
                    string html = File.ReadAllText(f);
                    if (html.IndexOf("class=" + '"' + "slide", StringComparison.Ordinal) < 0) { continue; }

                    string 원본 = html;
                    foreach (string 표시 in 예시표시)
                    {
                        while (true)
                        {
                            int at = html.IndexOf(표시, StringComparison.Ordinal);
                            if (at < 0) { break; }
                            int s0 = html.LastIndexOf("<section", at, StringComparison.Ordinal);
                            int e0 = html.IndexOf("</section>", at, StringComparison.Ordinal);
                            if (s0 < 0 || e0 < 0) { break; }
                            e0 += "</section>".Length;
                            // 첫 장(표지)은 남긴다. 지우면 아무것도 안 보이게 된다.
                            if (html.IndexOf("<section", StringComparison.Ordinal) == s0) { break; }
                            html = html.Substring(0, s0) + html.Substring(e0);
                        }
                    }
                    if (html != 원본)
                    {
                        File.WriteAllText(f, html);
                        고친파일++;
                    }
                }
                catch { }
            }
        }
        return 고친파일;
    }

    [STAThread]
    static int Main()
    {
        string 받을곳 = Path.Combine(Path.GetTempPath(),
            "camp-tools-" + Guid.NewGuid().ToString("N") + ".zip");
        string 넣을곳 = ToolsDir();

        try
        {
            // 옛 윈도우에서도 되게 TLS 1.2 를 켠다.
            // 안 켜면 .NET 기본값이 TLS 1.0 이라 서버가 끊어 버린다.
            try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; }
            catch { }

            using (var wc = new WebClient())
            {
                wc.DownloadFile("__URL__", 받을곳);
            }

            if (!Directory.Exists(넣을곳)) { Directory.CreateDirectory(넣을곳); }

            // zip 은 두 갈래다.
            //   tools/...   -> %LOCALAPPDATA%\Programs\camp-tools   (그림·영상 도구)
            //   preset/...  -> %USERPROFILE%\.config\opencode        (도우미 설정)
            //
            // opencode.json 은 일부러 안 건드린다. 설치할 때 그 파일에 셸 경로를
            // 넣어 두는데, 덮어쓰면 그게 지워져서 .sh 도구가 전부 죽는다.
            string 열쇠곳 = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".config\\camp");
            string 설정곳 = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".config\\opencode");

            int 바꾼수 = 0;
            using (var zip = ZipFile.OpenRead(받을곳))
            {
                foreach (var e in zip.Entries)
                {
                    if (string.IsNullOrEmpty(e.Name)) { continue; }
                    string 안쪽 = e.FullName.Replace('/', '\\');
                    string 뿌리;
                    string 나머지;
                    if (안쪽.StartsWith("tools\\", StringComparison.OrdinalIgnoreCase))
                    {
                        뿌리 = 넣을곳; 나머지 = 안쪽.Substring(6);
                    }
                    else if (안쪽.StartsWith("preset\\", StringComparison.OrdinalIgnoreCase))
                    {
                        뿌리 = 설정곳; 나머지 = 안쪽.Substring(7);
                    }
                    else if (안쪽.StartsWith("keys\\", StringComparison.OrdinalIgnoreCase))
                    {
                        // 그림·영상 열쇠. 만들 곳을 늘리면 여기로 보내야
                        // 이미 설치한 학생도 새 곳을 쓸 수 있다.
                        뿌리 = 열쇠곳; 나머지 = 안쪽.Substring(5);
                    }
                    else { continue; }

                    if (!Directory.Exists(뿌리)) { Directory.CreateDirectory(뿌리); }
                    string 기준 = Path.GetFullPath(뿌리);
                    string 갈곳 = Path.GetFullPath(Path.Combine(뿌리, 나머지));
                    if (!갈곳.StartsWith(기준, StringComparison.OrdinalIgnoreCase)) { continue; }
                    string 부모 = Path.GetDirectoryName(갈곳);
                    if (!Directory.Exists(부모)) { Directory.CreateDirectory(부모); }
                    e.ExtractToFile(갈곳, true);      // 덮어쓴다. 이게 목적이다.
                    바꾼수++;
                }
            }

            if (바꾼수 == 0)
            {
                MessageBox.Show(
                    "고칠 것을 받지 못했어요.\n선생님을 불러 주세요.",
                    "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 1;
            }

            // 앱이 켜져 있으면 옛 설정을 붙들고 있다. 그래서 우리가 꺼 준다.
            //
            // 왜 (실측, 2026-09-05 현장): "닫았다 켜세요" 라고 글로 알려 줬는데
            // 학생이 창만 닫고 프로세스는 남아서, 고쳤는데도 안 고쳐진 것처럼
            // 보였다. 사람에게 시키지 말고 도구가 하는 편이 확실하다.
            // 바뀐 설정을 학생이 확실히 쓰게 하려면 새 대화로 시작해야 한다.
            // 말로 알려 주면 아무도 안 읽는다. 표를 남겨 두면 "캠프 시작" 이
            // 그걸 보고 알아서 새 대화를 열어 준다.
            try
            {
                string 방 = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "창의디자인캠프");
                if (!Directory.Exists(방)) { Directory.CreateDirectory(방); }
                File.WriteAllText(Path.Combine(방, "새대화필요.txt"),
                    "도구를 고쳤습니다. 캠프 시작이 새 대화를 열어 줍니다.");
            }
            catch { }

            int 치운발표자료 = 예시장지우기();

            int 끈것 = 0;
            try
            {
                foreach (var pr in System.Diagnostics.Process.GetProcessesByName("OpenCode"))
                {
                    try { pr.Kill(); 끈것++; } catch { }
                }
            }
            catch { }

            MessageBox.Show(
                "다 고쳤어요! (" + 바꾼수 + "개)" +
                (치운발표자료 > 0 ? "\n발표자료에서 빈 예시 장도 치웠어요." : "") + "\n\n" +
                "이제 영상 만들기가 되고," + "\n" +
                "도우미가 사진도 볼 수 있어요." + "\n\n" +
                (끈것 > 0
                    ? "캠프 앱을 껐어요." + "\n" +
                      "바탕화면의 캠프 시작 을 다시 눌러 주세요." + "\n" +
                      "새 대화가 저절로 열려요. 거기서부터 하면 돼요."
                    : "캠프 시작 을 눌러 주세요." + "\n" +
                      "새 대화가 저절로 열려요."),
                "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }
        catch (WebException)
        {
            MessageBox.Show(
                "캠프 와이파이에 연결되어 있는지 확인해 주세요.\n\n" +
                "연결돼 있는데도 안 되면 선생님을 불러 주세요.",
                "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "고치지 못했어요. 선생님을 불러 주세요.\n\n" + ex.Message,
                "창의디자인캠프", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        finally
        {
            try { if (File.Exists(받을곳)) { File.Delete(받을곳); } } catch { }
        }
    }
}
'@

function Invoke-BuildFixTools {
    param([string]$RepoDir, [string]$Url = 'http://192.168.0.5/tools.zip')

    $csc = Get-CscPath
    if ($null -eq $csc) { Write-Host 'csc.exe 를 찾지 못했습니다.'; return 1 }

    # --- 도구 묶음부터 만든다 ---
    $tools = Join-Path $RepoDir 'dist\tools'
    if (-not (Test-Path -LiteralPath $tools -PathType Container)) {
        Write-Host 'dist\tools 가 없습니다. build-dist.ps1 을 먼저 실행하세요.'
        return 1
    }
    $공유 = Join-Path $RepoDir 'lan-share'
    if (-not (Test-Path -LiteralPath $공유)) { New-Item -ItemType Directory -Path $공유 -Force | Out-Null }
    $zip = Join-Path $공유 'tools.zip'
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    $preset = Join-Path $RepoDir 'dist\preset'
    $임시2 = Join-Path $env:TEMP ('campfixzip-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $임시2 'tools') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $임시2 'preset') -Force | Out-Null
    try {
        Copy-Item -Path (Join-Path $tools '*') -Destination (Join-Path $임시2 'tools') -Recurse -Force
        # opencode.json 은 넣지 않는다. 설치할 때 거기에 셸 경로를 써 넣는데
        # 덮어쓰면 그게 지워져서 그림·영상·합치기가 전부 죽는다.
        # node_modules 도 넣지 않는다. 61MB 라 "작은 파일" 이 아니게 된다.
        foreach ($ㅈ in @('agent', 'command', 'skills')) {
            $원 = Join-Path $preset $ㅈ
            if (Test-Path -LiteralPath $원 -PathType Container) {
                Copy-Item -LiteralPath $원 -Destination (Join-Path $임시2 'preset') -Recurse -Force
            }
        }
        # 열쇠도 같이 보낸다. fal 열쇠를 새로 넣었는데 이미 설치한 학생에게는
        # 그게 없어서, 구글이 막히면 갈 곳이 없다(실측 2026-09-05).
        $열쇠원본 = Join-Path $RepoDir 'dist\secrets\media-keys.env'
        if (Test-Path -LiteralPath $열쇠원본 -PathType Leaf) {
            New-Item -ItemType Directory -Path (Join-Path $임시2 'keys') -Force | Out-Null
            Copy-Item -LiteralPath $열쇠원본 -Destination (Join-Path $임시2 'keys') -Force
        }

        $원 = Join-Path $preset 'AGENTS.md'
        if (Test-Path -LiteralPath $원 -PathType Leaf) {
            Copy-Item -LiteralPath $원 -Destination (Join-Path $임시2 'preset') -Force
        }
        Compress-Archive -Path (Join-Path $임시2 '*') -DestinationPath $zip -CompressionLevel Optimal
    }
    finally {
        Remove-Item -LiteralPath $임시2 -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ('  tools.zip  ' + [math]::Round((Get-Item $zip).Length / 1KB, 1) + ' KB')

    # --- exe 를 만든다 ---
    $icon = Join-Path $RepoDir 'dist\scripts\camp.ico'
    $tmp = Join-Path $env:TEMP ('campfix-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $cs = $CsSource.Replace('__URL__', $Url)
        $csFile = Join-Path $tmp 'Fix.cs'
        [System.IO.File]::WriteAllText($csFile, $cs, (New-Object System.Text.UTF8Encoding($true)))

        $outExe = Join-Path $공유 '도구 고치기.exe'
        if (Test-Path -LiteralPath $outExe) { Remove-Item -LiteralPath $outExe -Force }

        $args = @(
            '/nologo', '/target:winexe', '/optimize+',
            '/reference:System.Windows.Forms.dll',
            '/reference:System.IO.Compression.dll',
            '/reference:System.IO.Compression.FileSystem.dll'
        )
        if (Test-Path -LiteralPath $icon -PathType Leaf) {
            $args += ('/win32icon:"' + $icon + '"')
        }
        $args += ('/out:"' + $outExe + '"')
        $args += ('"' + $csFile + '"')

        $p = Start-Process -FilePath $csc -ArgumentList $args -PassThru -Wait -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $tmp 'out.txt') `
                -RedirectStandardError  (Join-Path $tmp 'err.txt')
        if ($p.ExitCode -ne 0) {
            Write-Host '컴파일 실패:'
            Get-Content -LiteralPath (Join-Path $tmp 'out.txt') -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { Write-Host ('  ' + $_) }
            Get-Content -LiteralPath (Join-Path $tmp 'err.txt') -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { Write-Host ('  ' + $_) }
            return 1
        }
        Write-Host ('  만들었어요: 도구 고치기.exe  (' + [math]::Round((Get-Item $outExe).Length / 1KB, 1) + ' KB)')
        Write-Host ('  받는 곳: ' + $Url)
        return 0
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    exit (Invoke-BuildFixTools -RepoDir $repo)
}
