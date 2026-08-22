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
           Url  = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/CascadiaCode.zip' }
    )
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

        # zip 은 서명 대상이 아니다
        if ($s.Name -like '*.zip') {
            Write-Host ('  (zip — 서명 대상 아님)')
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
