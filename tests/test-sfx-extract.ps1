$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$Repo\dist\scripts\lib-assert.ps1"

# 설치 파일(SFX)이 압축을 풀 때 이미 있는 파일을 덮어쓸 수 있어야 한다.
#
# 왜 필요한가: ZipFile.ExtractToDirectory 는 대상 파일이 하나라도 있으면
# IOException 을 던지고 통째로 멈춘다. SFX 는 먼저 폴더를 지우려 하지만,
# "점검" 창을 열어 둔 채로 다시 설치하면 그 지우기가 실패한다.
# 그러면 "준비하지 못했어요" 로 끝난다 — 다시 설치가 아예 안 되는 것이다.
#
# 이 테스트는 build-installer-exe.ps1 안에 실제로 들어가는 C# 코드를
# 그대로 꺼내 컴파일해서 시험한다. 복사본을 시험하면 의미가 없다.

function Get-CscPath {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $csc) { return $null }
    return $csc.FullName
}

# 중괄호를 세어 메서드 본문만 정확히 꺼낸다
function Get-CsMethod([string]$Source, [string]$Signature) {
    $start = $Source.IndexOf($Signature)
    if ($start -lt 0) { return $null }
    $i = $Source.IndexOf('{', $start)
    if ($i -lt 0) { return $null }
    $depth = 0
    for ($j = $i; $j -lt $Source.Length; $j++) {
        if ($Source[$j] -eq '{') { $depth++ }
        elseif ($Source[$j] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Source.Substring($start, $j - $start + 1) }
        }
    }
    return $null
}

$build = Get-Content -LiteralPath "$Repo\scripts\build-installer-exe.ps1" -Raw -Encoding UTF8
Assert-Contains $build 'ExtractOverwrite' '빌드 스크립트가 ExtractOverwrite 를 씀'
Assert-NotContains $build 'ZipFile.ExtractToDirectory(tmpZip, dest)' '덮어쓰기 못 하는 추출을 쓰지 않음'

$method = Get-CsMethod -Source $build -Signature 'static void ExtractOverwrite'
Assert-True ($null -ne $method) 'ExtractOverwrite 코드를 꺼냄'

$csc = Get-CscPath
Assert-True ($null -ne $csc) 'csc.exe 있음'

$tmp = Join-Path $env:TEMP ("sfxtest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    # --- 시험용 zip 만들기 ---
    $srcDir = Join-Path $tmp 'src'
    New-Item -ItemType Directory -Path (Join-Path $srcDir 'scripts') -Force | Out-Null
    'AAA'      | Set-Content -LiteralPath (Join-Path $srcDir 'top.txt') -Encoding ascii
    'SCRIPT-1' | Set-Content -LiteralPath (Join-Path $srcDir 'scripts\a.ps1') -Encoding ascii
    'SCRIPT-2' | Set-Content -LiteralPath (Join-Path $srcDir 'scripts\b.ps1') -Encoding ascii
    $zip = Join-Path $tmp 'payload.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($srcDir, $zip)

    # --- 실제 코드를 넣은 시험 프로그램 컴파일 ---
    $prog = @"
using System;
using System.IO;
using System.IO.Compression;

static class Program
{
$method

    static int Main(string[] args)
    {
        try { ExtractOverwrite(args[0], args[1]); Console.WriteLine("OK"); return 0; }
        catch (Exception ex) { Console.WriteLine("ERR " + ex.GetType().Name + " " + ex.Message); return 1; }
    }
}
"@
    $cs  = Join-Path $tmp 'prog.cs'
    $exe = Join-Path $tmp 'prog.exe'
    [System.IO.File]::WriteAllText($cs, $prog, (New-Object System.Text.UTF8Encoding($false)))
    $out = & $csc /nologo /target:exe /out:"$exe" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll "$cs" 2>&1
    Assert-FileExists $exe ('시험 프로그램 컴파일 성공 ' + ($out -join ' '))

    $dest = Join-Path $tmp 'dest'

    # --- 1회차: 빈 폴더에 풀기 ---
    $r1 = & $exe $zip $dest 2>&1
    Assert-Eq ($r1 -join '') 'OK' '빈 폴더에 풀기 성공'
    Assert-FileExists (Join-Path $dest 'top.txt') 'top.txt 나옴'
    Assert-FileExists (Join-Path $dest 'scripts\a.ps1') 'scripts\a.ps1 나옴'

    # --- 2회차: 이미 파일이 있는 폴더에 다시 풀기 (핵심) ---
    'OLD' | Set-Content -LiteralPath (Join-Path $dest 'top.txt') -Encoding ascii
    $r2 = & $exe $zip $dest 2>&1
    Assert-Eq ($r2 -join '') 'OK' '이미 파일이 있어도 풀기 성공 (덮어쓰기)'
    Assert-Eq ((Get-Content (Join-Path $dest 'top.txt') -Raw).Trim()) 'AAA' '내용이 새것으로 덮어써짐'

    # --- 3회차: 읽기전용 파일도 덮어쓰는지 ---
    $ro = Join-Path $dest 'scripts\a.ps1'
    'STALE' | Set-Content -LiteralPath $ro -Encoding ascii
    Set-ItemProperty -LiteralPath $ro -Name IsReadOnly -Value $true
    $r3 = & $exe $zip $dest 2>&1
    Assert-Eq ($r3 -join '') 'OK' '읽기전용 파일이 있어도 풀기 성공'
    Assert-Eq ((Get-Content $ro -Raw).Trim()) 'SCRIPT-1' '읽기전용 파일도 새것으로 덮어써짐'

    # --- 4회차: 경로 탈출 막는지 ---
    $bad = Join-Path $tmp 'bad.zip'
    $fs = [System.IO.File]::Create($bad)
    $za = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    $e = $za.CreateEntry('../탈출.txt')
    $sw = New-Object System.IO.StreamWriter($e.Open())
    $sw.Write('나쁜것'); $sw.Dispose(); $za.Dispose(); $fs.Dispose()
    $dest2 = Join-Path $tmp 'dest2'
    $r4 = & $exe $bad $dest2 2>&1
    Assert-Eq ($r4 -join '') 'OK' '탈출 시도 zip 도 예외 없이 처리'
    Assert-True (-not (Test-Path (Join-Path $tmp '탈출.txt'))) '대상 폴더 밖에 파일이 안 만들어짐'
}
finally {
    Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.IsReadOnly = $false } catch { } }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Summary) { exit 0 } else { exit 1 }
