# 배포판 진입점을 아이콘 있는 .exe 로 만든다.
#
# 왜 .exe 인가: .cmd 더블클릭은 동작하지만 검은 콘솔이 뜨고 아이콘이 없어
# "도구" 처럼 보이지 않는다. 주최측에 보여줄 물건이므로 껍데기를 갖춘다.
#
# 어떻게: Windows 에 기본으로 있는 csc.exe(.NET Framework 4)로 아주 작은
# WinExe 를 컴파일한다. 별도 툴체인을 설치하지 않는다.
# .exe 는 창이 없고(WinExe) PowerShell GUI 를 숨긴 콘솔로 띄운 뒤 기다린다.
#
# .cmd 진입점도 그대로 남긴다. SmartScreen 반응이 나쁜 노트북에서 쓸
# 백업 경로다 — 비용이 거의 없다.

$ErrorActionPreference = 'Stop'

function Get-CscPath {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $csc) {
        $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1
    }
    if ($null -eq $csc) { return $null }
    return $csc.FullName
}

# 진입점 정의. Command 는 powershell -Command 에 넘길 문장이다.
function Get-ExeTargets {
    return @(
        @{
            Exe   = '창의디자인캠프 설치.exe'
            Title = '창의디자인캠프 설치'
            Load  = 'lib-log.ps1,lib-gui.ps1,lib-appstate.ps1,lib-team.ps1,selfcheck.ps1,orchestrator.ps1,gui-install.ps1'
            Call  = 'Show-CampInstaller -DistDir $root'
        },
        @{
            Exe   = '캠프 시작.exe'
            Title = '창의디자인캠프 시작'
            Load  = 'lib-log.ps1,lib-gui.ps1,lib-appstate.ps1,lib-team.ps1,launcher.ps1,gui-launcher.ps1'
            Call  = 'Show-CampLauncher -TemplateDir (Join-Path $root ''template'')'
        },
        @{
            Exe   = '점검.exe'
            Title = '창의디자인캠프 점검'
            Load  = 'lib-log.ps1,lib-gui.ps1,selfcheck.ps1,gui-check.ps1'
            Call  = 'Show-CampChecker'
        }
    )
}

function Build-CampExe {
    param(
        [string]$RepoDir,
        [string]$Csc,
        [hashtable]$Target
    )

    $distDir = Join-Path $RepoDir 'dist'
    $icon = Join-Path $distDir 'scripts\camp.ico'
    if (-not (Test-Path -LiteralPath $icon -PathType Leaf)) {
        Write-Host '아이콘이 없습니다. make-icon.ps1 을 먼저 실행하세요.'
        return $false
    }

    # PowerShell 한 줄. 자기 위치(exe 폴더)를 기준으로 스크립트를 불러온다.
    $loads = ($Target.Load -split ',') | ForEach-Object { '. (Join-Path $root ''scripts\' + $_ + ''');' }
    $psCommand = '$root = $args[0]; ' + ($loads -join ' ') + ' exit (' + $Target.Call + ')'

    $cs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

static class Program {
    [STAThread]
    static int Main() {
        string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string ps = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell\\v1.0\\powershell.exe");
        if (!File.Exists(ps)) { ps = "powershell.exe"; }

        var psi = new ProcessStartInfo();
        psi.FileName = ps;
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -Command \"& {__COMMAND__}\" \"" + exeDir + "\"";
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = exeDir;

        try {
            using (var p = Process.Start(psi)) {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex) {
            MessageBox.Show(
                "도구를 실행할 수 없어요. 선생님을 불러 주세요.\n\n" + ex.Message,
                "__TITLE__", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
    }
}
'@

    # C# 문자열 리터럴에 넣기 위해 따옴표를 이스케이프한다
    $escaped = $psCommand.Replace('\', '\\').Replace('"', '\"')
    $cs = $cs.Replace('__COMMAND__', $escaped).Replace('__TITLE__', $Target.Title)

    $tmp = Join-Path $env:TEMP ('campexe-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $csFile = Join-Path $tmp 'Program.cs'
        [System.IO.File]::WriteAllText($csFile, $cs, (New-Object System.Text.UTF8Encoding($true)))
        $outExe = Join-Path $distDir $Target.Exe

        # 경로에 공백이 들어가므로 반드시 인용한다.
        # 안 하면 "창의디자인캠프 설치.exe" 가 두 인자로 쪼개져 CS2001 이 난다(실측).
        $args = @(
            '/nologo',
            '/target:winexe',
            '/optimize+',
            ('/win32icon:"' + $icon + '"'),
            '/reference:System.Windows.Forms.dll',
            ('/out:"' + $outExe + '"'),
            ('"' + $csFile + '"')
        )
        $p = Start-Process -FilePath $Csc -ArgumentList $args -PassThru -Wait -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $tmp 'out.txt') `
                -RedirectStandardError  (Join-Path $tmp 'err.txt')
        if ($p.ExitCode -ne 0) {
            Write-Host ('컴파일 실패: ' + $Target.Exe)
            Get-Content -LiteralPath (Join-Path $tmp 'out.txt') -ErrorAction SilentlyContinue | Select-Object -First 6 | ForEach-Object { Write-Host ('  ' + $_) }
            Get-Content -LiteralPath (Join-Path $tmp 'err.txt') -ErrorAction SilentlyContinue | Select-Object -First 6 | ForEach-Object { Write-Host ('  ' + $_) }
            return $false
        }
        return (Test-Path -LiteralPath $outExe -PathType Leaf)
    }
    finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

function Invoke-BuildExe([string]$RepoDir) {
    $csc = Get-CscPath
    if ($null -eq $csc) {
        Write-Host 'csc.exe 를 찾을 수 없습니다 (.NET Framework 필요).'
        return 1
    }
    Write-Host ('컴파일러: ' + $csc)

    $fail = 0
    foreach ($t in (Get-ExeTargets)) {
        if (Build-CampExe -RepoDir $RepoDir -Csc $csc -Target $t) {
            $size = (Get-Item (Join-Path $RepoDir ('dist\' + $t.Exe))).Length / 1KB
            Write-Host ('  만들었어요: ' + $t.Exe + ' (' + [math]::Round($size, 1) + 'KB)')
        }
        else { $fail++ }
    }
    if ($fail -gt 0) { return 1 }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    exit (Invoke-BuildExe -RepoDir $repo)
}
