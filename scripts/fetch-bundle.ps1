# 배포판 구성요소를 내려받고 코드 서명을 검증한다.
# 서명이 유효하지 않은 파일은 학생 노트북에 넣지 않는다.

function Get-BundleSources {
    return @(
        @{ Name = 'opencode-desktop-win-x64.exe'
           Url  = 'https://github.com/anomalyco/opencode/releases/download/v1.18.20/opencode-desktop-win-x64.exe' },
        @{ Name = 'opencode-windows-x64.zip'
           Url  = 'https://github.com/anomalyco/opencode/releases/download/v1.18.20/opencode-windows-x64.zip' },
        @{ Name = 'node-lts-x64.msi'
           Url  = 'https://nodejs.org/dist/v22.20.0/node-v22.20.0-x64.msi' },
        @{ Name = 'python-3.12-amd64.exe'
           Url  = 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe' },
        @{ Name = 'Git-64-bit.exe'
           Url  = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe' },
        @{ Name = 'CascadiaCode-NF.zip'
           Url  = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/CascadiaCode.zip' },
        # MSI 는 Program Files 에 넣느라 관리자 권한을 요구한다.
        # 학생 노트북에서 관리자 암호를 물으면 거기서 멈춘다 — zip 을 쓴다.
        @{ Name = 'gh-windows-amd64.zip'
           Url  = 'https://github.com/cli/cli/releases/download/v2.98.0/gh_2.98.0_windows_amd64.zip' }
    )
}

# zip 안에 든 .exe 의 서명을 확인한다.
# 반환: @{ Count = 실행파일 수; Bad = 실패한 파일들; Signer = 서명자 }
function Test-ZipSignatures([string]$ZipPath) {
    $tmp = Join-Path $env:TEMP ('zipsig-' + [guid]::NewGuid().ToString('N'))
    $bad = @(); $count = 0; $signer = ''
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $tmp)
        foreach ($f in (Get-ChildItem -LiteralPath $tmp -Recurse -Filter '*.exe' -File)) {
            $count++
            $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
            if ($sig.Status -ne 'Valid') { $bad += ($f.Name + '(' + $sig.Status + ')') }
            elseif (-not $signer) { $signer = [string]$sig.SignerCertificate.Subject }
        }
    }
    catch {
        # 열어보지 못하면 판단할 수 없다. 통과시키지 않는다.
        $bad += ('zip 을 열 수 없음: ' + $_.Exception.Message)
        $count++
    }
    finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    return @{ Count = $count; Bad = $bad; Signer = $signer }
}

function Invoke-FetchBundle([string]$BundleDir) {
    if (-not (Test-Path -LiteralPath $BundleDir)) {
        New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
    }
    $failed = @()
    foreach ($s in (Get-BundleSources)) {
        $dest = Join-Path $BundleDir $s.Name
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            Write-Host ('이미 있음: ' + $s.Name)
        }
        else {
            Write-Host ('받는 중: ' + $s.Name)
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $s.Url -OutFile $dest -UseBasicParsing
            }
            catch {
                Write-Host ('  실패: ' + $s.Name + ' — ' + $_.Exception.Message)
                $failed += $s.Name
                continue
            }
        }

        # zip 자체에는 서명이 없다. 하지만 안에 든 .exe 는 서명돼 있다.
        # "서명 안 된 것은 학생 노트북에 넣지 않는다" 는 원칙은 zip 에도 적용한다.
        if ($s.Name -like '*.zip') {
            $inner = Test-ZipSignatures -ZipPath $dest
            if ($inner.Count -eq 0) {
                Write-Host ('  (zip — 실행 파일 없음)')
            }
            elseif ($inner.Bad.Count -gt 0) {
                Write-Host ('  zip 안의 서명 검증 실패: ' + ($inner.Bad -join ', '))
                Remove-Item -LiteralPath $dest -Force
                $failed += $s.Name
            }
            else {
                Write-Host ('  zip 안 실행 파일 ' + $inner.Count + '개 서명 확인: ' + $inner.Signer)
            }
            continue
        }

        $sig = Get-AuthenticodeSignature -LiteralPath $dest
        if ($sig.Status -ne 'Valid') {
            Write-Host ('  서명 검증 실패(' + $sig.Status + '): ' + $s.Name)
            Remove-Item -LiteralPath $dest -Force
            $failed += $s.Name
        }
        else {
            Write-Host ('  서명 확인: ' + $sig.SignerCertificate.Subject)
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host ('받지 못한 파일: ' + ($failed -join ', '))
        return 1
    }
    Write-Host ''
    Write-Host '번들 수집 완료.'
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    exit (Invoke-FetchBundle -BundleDir (Join-Path $repo 'dist\bundle'))
}
