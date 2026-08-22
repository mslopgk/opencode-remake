# 배포판 아이콘을 만든다.
#
# 외부 이미지 파일에 의존하지 않고 코드로 그린다. 저장소에 바이너리를 넣지
# 않아도 되고, 색을 발표자료 테마와 한 곳에서 맞출 수 있다.
#
# 모티프: 캠페인 주제가 "지구·환경 / AI·디지털" 이고 발표자료 기본 테마가
# ocean 이므로, 심해 바탕 위 물결 세 줄 + 위쪽에 작은 빛점.
# 16~256px 여러 크기를 한 .ico 에 담는다.

Add-Type -AssemblyName System.Drawing

function New-CampIconBitmap([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    $bg     = [System.Drawing.Color]::FromArgb(255, 11, 37, 69)    # #0B2545
    $accent = [System.Drawing.Color]::FromArgb(255, 91, 192, 235)  # #5BC0EB
    $sub    = [System.Drawing.Color]::FromArgb(255, 168, 218, 220) # #A8DADC

    # 둥근 사각 바탕
    $r = [int]($Size * 0.22)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($Size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $Size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush($bg)
    $g.FillPath($brush, $path)

    # 물결 두 줄. 16px 에서도 읽히도록 진폭을 크게, 획을 굵게 잡는다.
    # 세 줄로 하면 작은 크기에서 뭉개져 흐물흐물한 직선처럼 보인다(실측).
    $penW = [Math]::Max(1.5, $Size * 0.095)
    $waves = @(
        @{ Y = 0.62; Col = $accent; A = 255 },
        @{ Y = 0.80; Col = $sub;    A = 150 }
    )
    foreach ($w in $waves) {
        $c = [System.Drawing.Color]::FromArgb($w.A, $w.Col.R, $w.Col.G, $w.Col.B)
        $pen = New-Object System.Drawing.Pen($c, $penW)
        $pen.StartCap = 'Round'
        $pen.EndCap = 'Round'
        $y = $Size * $w.Y
        $amp = $Size * 0.14          # 진폭을 키워 실제로 물결로 보이게
        $x0 = $Size * 0.15
        $x1 = $Size * 0.85
        $span = $x1 - $x0
        # 산 하나 골 하나 — 두 개의 베지어로 S 자를 만든다
        $g.DrawBezier($pen, $x0, $y,
            ($x0 + $span * 0.17), ($y - $amp),
            ($x0 + $span * 0.33), ($y - $amp),
            ($x0 + $span * 0.5), $y)
        $g.DrawBezier($pen, ($x0 + $span * 0.5), $y,
            ($x0 + $span * 0.67), ($y + $amp),
            ($x0 + $span * 0.83), ($y + $amp),
            $x1, $y)
        $pen.Dispose()
    }

    # 위쪽 빛점 — 생성형 AI 쪽 상징. 작은 크기에서도 보이게 키운다
    $dotR = $Size * 0.155
    $dotBrush = New-Object System.Drawing.SolidBrush($accent)
    $g.FillEllipse($dotBrush, ($Size * 0.5 - $dotR / 2), ($Size * 0.30 - $dotR / 2), $dotR, $dotR)
    $dotBrush.Dispose()

    $brush.Dispose(); $path.Dispose(); $g.Dispose()
    return $bmp
}

function New-CampIcon([string]$OutPath) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngs = @()
    foreach ($s in $sizes) {
        $bmp = New-CampIconBitmap -Size $s
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += ,@{ Size = $s; Bytes = $ms.ToArray() }
        $ms.Dispose(); $bmp.Dispose()
    }

    $fs = [System.IO.File]::Create($OutPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0)                 # reserved
        $bw.Write([uint16]1)                 # type: icon
        $bw.Write([uint16]$pngs.Count)

        $offset = 6 + (16 * $pngs.Count)
        foreach ($p in $pngs) {
            $dim = $p.Size
            if ($dim -ge 256) { $dim = 0 }
            $bw.Write([byte]$dim)            # width
            $bw.Write([byte]$dim)            # height
            $bw.Write([byte]0)               # palette
            $bw.Write([byte]0)               # reserved
            $bw.Write([uint16]1)             # color planes
            $bw.Write([uint16]32)            # bpp
            $bw.Write([uint32]$p.Bytes.Length)
            $bw.Write([uint32]$offset)
            $offset += $p.Bytes.Length
        }
        foreach ($p in $pngs) { $bw.Write($p.Bytes) }
    }
    finally { $bw.Flush(); $bw.Dispose(); $fs.Dispose() }

    return (Test-Path -LiteralPath $OutPath -PathType Leaf)
}

if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $out = Join-Path $repo 'dist\scripts\camp.ico'
    if (New-CampIcon -OutPath $out) {
        Write-Host ('아이콘 생성: ' + $out + ' (' + [math]::Round((Get-Item $out).Length/1KB,1) + 'KB)')
        exit 0
    }
    Write-Host '아이콘 생성 실패'
    exit 1
}
