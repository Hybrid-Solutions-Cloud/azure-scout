#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Render report figures to PNG with no external dependency.

.DESCRIPTION
    AB#6737 / AB#6885, clauses D-01, D-02, D-03 and W-12.

    Phase 0's finding was that the diagram pipeline emits `.drawio` XML and nothing else, so no
    document could embed a figure even when one had been generated. Every attempt to fix that so
    far has proposed a dependency — Graphviz for AzViz, a headless browser for draw.io export,
    ImageMagick — and every one of them fails the same test: Scout is a PowerShell module people
    install from the gallery and run on a laptop, and a report that silently loses its figures
    because a native binary is missing is worse than one that never promised them.

    So this rasterises in managed code. A PNG is a zlib stream of filtered scanlines wrapped in
    four chunks; zlib's STORED block type needs no compressor, only the two checksums. That is
    the whole trick, and it is why this file has no `Add-Type`, no P/Invoke and no `dotnet`
    acquire — unlike Export-Word.ps1, which genuinely needs the OpenXML SDK.

    System.Drawing is deliberately not used: `System.Drawing.Common` is Windows-only from .NET 6
    onwards, and this module is expected to run wherever PowerShell 7 does.

    What it draws is the set of figures the assessment report actually argues with — alignment
    by area, control status composition, and a severity-by-area heatmap. It is not a general
    graphics library and should not grow into one.

.NOTES
    Text is drawn from a 5x7 bitmap font. That is a deliberate ceiling: a figure label is a word
    or a number, and a renderer that needed real typography would need a font file, which is a
    dependency again.
#>

#region PNG encoding

# Declared at script scope rather than created on first use inside the function: under
# Set-StrictMode -Version Latest, reading an unset variable THROWS rather than returning $null,
# so the usual `if (-not $Script:Table)` lazy-init pattern fails on its own guard. This is the
# same StrictMode class documented across this repo.
$Script:ScoutCrcTable = $null

function Get-ScoutPngCrc32 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    # PowerShell parses the literal 0xFFFFFFFF as Int32 -1, not as a uint32, so every constant
    # here goes through [uint32]::MaxValue or an explicit cast. Getting that wrong produces a
    # "cannot convert -1 to UInt32" a long way from its cause.
    $poly = [uint32]3988292384   # 0xEDB88320, reversed CRC-32 polynomial
    $allOnes = [uint32]::MaxValue

    if (-not $Script:ScoutCrcTable) {
        $Script:ScoutCrcTable = [uint32[]]::new(256)
        for ($n = 0; $n -lt 256; $n++) {
            [uint32]$c = [uint32]$n
            for ($k = 0; $k -lt 8; $k++) {
                if (($c -band [uint32]1) -ne 0) { $c = [uint32]($poly -bxor ($c -shr 1)) }
                else { $c = [uint32]($c -shr 1) }
            }
            $Script:ScoutCrcTable[$n] = $c
        }
    }

    [uint32]$crc = $allOnes
    foreach ($b in $Bytes) {
        $idx = [int](($crc -bxor [uint32]$b) -band [uint32]0xFF)
        $crc = [uint32]($Script:ScoutCrcTable[$idx] -bxor ($crc -shr 8))
    }
    return [uint32]($crc -bxor $allOnes)
}

function Get-ScoutPngAdler32 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [uint32]$a = 1
    [uint32]$b = 0
    foreach ($byte in $Bytes) {
        $a = [uint32](($a + $byte) % 65521)
        $b = [uint32](($b + $a) % 65521)
    }
    return [uint32](($b -shl 16) -bor $a)
}

function ConvertTo-ScoutBigEndian {
    param([Parameter(Mandatory)][uint32]$Value)
    return [byte[]]@(
        [byte](($Value -shr 24) -band 0xFF)
        [byte](($Value -shr 16) -band 0xFF)
        [byte](($Value -shr 8) -band 0xFF)
        [byte]($Value -band 0xFF)
    )
}

function New-ScoutPngChunk {
    param([Parameter(Mandatory)][string]$Type, [byte[]]$Data = @())
    $typeBytes = [System.Text.Encoding]::ASCII.GetBytes($Type)
    $payload = [byte[]]($typeBytes + $Data)
    return [byte[]](
        (ConvertTo-ScoutBigEndian ([uint32]$Data.Length)) +
        $payload +
        (ConvertTo-ScoutBigEndian (Get-ScoutPngCrc32 -Bytes $payload))
    )
}

function ConvertTo-ScoutZlibStream {
    <#
    .SYNOPSIS
        Wrap raw bytes in a zlib stream.

    .DESCRIPTION
        `System.IO.Compression.DeflateStream` produces a RAW deflate stream and ships in the base
        class library, so the compression itself costs no dependency. zlib is that raw stream
        plus a two-byte header and a trailing Adler-32, both of which are trivial to add — which
        is the whole reason a PNG can be written from managed code with nothing installed.

        The header bytes are 0x78 0x01: deflate, 32K window, no preset dictionary, and check
        bits chosen so (CMF * 256 + FLG) is divisible by 31.
    #>
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $ms = [System.IO.MemoryStream]::new()
    try {
        $deflate = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        try { $deflate.Write($Bytes, 0, $Bytes.Length) } finally { $deflate.Dispose() }
        $compressed = $ms.ToArray()
    }
    finally { $ms.Dispose() }

    return [byte[]](
        [byte[]]@(0x78, 0x01) +
        $compressed +
        (ConvertTo-ScoutBigEndian (Get-ScoutPngAdler32 -Bytes $Bytes))
    )
}

function ConvertTo-ScoutPngBytes {
    <#
    .SYNOPSIS
        Encode an RGB pixel buffer as a PNG.

    .PARAMETER Pixels
        Row-major RGB triples: 3 bytes per pixel, Width * Height * 3 in total.
    #>
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][byte[]]$Pixels
    )

    $expected = $Width * $Height * 3
    if ($Pixels.Length -ne $expected) {
        throw "ConvertTo-ScoutPngBytes: expected $expected pixel bytes for ${Width}x${Height}, got $($Pixels.Length)."
    }

    # Each scanline is prefixed with its filter type. 0 (None) keeps the encoder honest and
    # costs only one byte a row; a real filter would need a compressor to pay for itself.
    $raw = [byte[]]::new($Height * (1 + $Width * 3))
    $stride = $Width * 3
    for ($y = 0; $y -lt $Height; $y++) {
        $dst = $y * (1 + $stride)
        $raw[$dst] = 0
        [Array]::Copy($Pixels, $y * $stride, $raw, $dst + 1, $stride)
    }

    $ihdr = [byte[]](
        (ConvertTo-ScoutBigEndian ([uint32]$Width)) +
        (ConvertTo-ScoutBigEndian ([uint32]$Height)) +
        [byte[]]@(8, 2, 0, 0, 0)   # 8-bit, truecolour RGB, deflate, adaptive filter, no interlace
    )

    $signature = [byte[]]@(137, 80, 78, 71, 13, 10, 26, 10)
    return [byte[]](
        $signature +
        (New-ScoutPngChunk -Type 'IHDR' -Data $ihdr) +
        (New-ScoutPngChunk -Type 'IDAT' -Data (ConvertTo-ScoutZlibStream -Bytes $raw)) +
        (New-ScoutPngChunk -Type 'IEND')
    )
}

#endregion

#region Canvas

function New-ScoutCanvas {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [string]$BackgroundHex = 'FFFFFF'
    )
    $rgb = ConvertFrom-ScoutHex -Hex $BackgroundHex
    $pixels = [byte[]]::new($Width * $Height * 3)
    # White is the overwhelmingly common background and a fresh byte[] is already zeroed, so a
    # non-white fill is the only case that needs the loop at all. On a 900x520 canvas that is
    # 1.4 million writes avoided per figure, which is the difference between a figure set that
    # renders in a second and one that renders in a minute.
    if ($rgb[0] -ne 0 -or $rgb[1] -ne 0 -or $rgb[2] -ne 0) {
        [Array]::Fill($pixels, [byte]0)
        for ($i = 0; $i -lt $pixels.Length; $i += 3) {
            $pixels[$i] = $rgb[0]; $pixels[$i + 1] = $rgb[1]; $pixels[$i + 2] = $rgb[2]
        }
    }
    return [pscustomobject]@{ Width = $Width; Height = $Height; Pixels = $pixels }
}

function ConvertFrom-ScoutHex {
    [OutputType([byte[]])]
    param([Parameter(Mandatory)][string]$Hex)
    $h = $Hex.TrimStart('#')
    return [byte[]]@(
        [Convert]::ToByte($h.Substring(0, 2), 16)
        [Convert]::ToByte($h.Substring(2, 2), 16)
        [Convert]::ToByte($h.Substring(4, 2), 16)
    )
}

function Set-ScoutCanvasPixel {
    param($Canvas, [int]$X, [int]$Y, [byte[]]$Rgb)
    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $Canvas.Width -or $Y -ge $Canvas.Height) { return }
    $i = ($Y * $Canvas.Width + $X) * 3
    $Canvas.Pixels[$i] = $Rgb[0]; $Canvas.Pixels[$i + 1] = $Rgb[1]; $Canvas.Pixels[$i + 2] = $Rgb[2]
}

function Set-ScoutCanvasRect {
    <#
    .SYNOPSIS
        Fill an axis-aligned rectangle.

    .DESCRIPTION
        The pixel writes are INLINE rather than routed through Set-ScoutCanvasPixel on purpose.
        A PowerShell function call costs microseconds, and a heatmap fills well over a hundred
        thousand pixels — going through the helper turns a one-second figure into a minute-long
        one. Clipping is done once against the rectangle instead of once per pixel for the same
        reason.
    #>
    param($Canvas, [int]$X, [int]$Y, [int]$Width, [int]$Height, [Parameter(Mandatory)][string]$Hex)
    if ($Width -le 0 -or $Height -le 0) { return }
    $rgb = ConvertFrom-ScoutHex -Hex $Hex
    $r = $rgb[0]; $g = $rgb[1]; $b = $rgb[2]

    $x0 = [Math]::Max(0, $X)
    $y0 = [Math]::Max(0, $Y)
    $x1 = [Math]::Min($Canvas.Width, $X + $Width)
    $y1 = [Math]::Min($Canvas.Height, $Y + $Height)
    if ($x1 -le $x0 -or $y1 -le $y0) { return }

    $pixels = $Canvas.Pixels
    $stride = $Canvas.Width * 3
    for ($yy = $y0; $yy -lt $y1; $yy++) {
        $i = $yy * $stride + $x0 * 3
        for ($xx = $x0; $xx -lt $x1; $xx++) {
            $pixels[$i] = $r; $pixels[$i + 1] = $g; $pixels[$i + 2] = $b
            $i += 3
        }
    }
}

#endregion

#region Bitmap text

# A 5x7 font, one hex byte per column, bit 0 = top row. Only the glyphs a figure label actually
# uses are defined; anything else falls back to a blank cell, which keeps a stray character from
# turning into a wrong one. Deliberately small: see this file's header on why there is no font
# file to load.
$Script:ScoutGlyphs = @{
    'A' = '7E', '11', '11', '11', '7E'
    'B' = '7F', '49', '49', '49', '36'
    'C' = '3E', '41', '41', '41', '22'
    'D' = '7F', '41', '41', '41', '3E'
    'E' = '7F', '49', '49', '49', '41'
    'F' = '7F', '09', '09', '09', '01'
    'G' = '3E', '41', '49', '49', '7A'
    'H' = '7F', '08', '08', '08', '7F'
    'I' = '00', '41', '7F', '41', '00'
    'J' = '20', '40', '41', '3F', '01'
    'K' = '7F', '08', '14', '22', '41'
    'L' = '7F', '40', '40', '40', '40'
    'M' = '7F', '02', '0C', '02', '7F'
    'N' = '7F', '04', '08', '10', '7F'
    'O' = '3E', '41', '41', '41', '3E'
    'P' = '7F', '09', '09', '09', '06'
    'Q' = '3E', '41', '51', '21', '5E'
    'R' = '7F', '09', '19', '29', '46'
    'S' = '46', '49', '49', '49', '31'
    'T' = '01', '01', '7F', '01', '01'
    'U' = '3F', '40', '40', '40', '3F'
    'V' = '1F', '20', '40', '20', '1F'
    'W' = '7F', '20', '18', '20', '7F'
    'X' = '63', '14', '08', '14', '63'
    'Y' = '03', '04', '78', '04', '03'
    'Z' = '61', '51', '49', '45', '43'
    '0' = '3E', '51', '49', '45', '3E'
    '1' = '00', '42', '7F', '40', '00'
    '2' = '42', '61', '51', '49', '46'
    '3' = '21', '41', '45', '4B', '31'
    '4' = '18', '14', '12', '7F', '10'
    '5' = '27', '45', '45', '45', '39'
    '6' = '3C', '4A', '49', '49', '30'
    '7' = '01', '71', '09', '05', '03'
    '8' = '36', '49', '49', '49', '36'
    '9' = '06', '49', '49', '29', '1E'
    '.' = '00', '60', '60', '00', '00'
    ',' = '00', '50', '30', '00', '00'
    ':' = '00', '36', '36', '00', '00'
    '-' = '08', '08', '08', '08', '08'
    '/' = '20', '10', '08', '04', '02'
    '%' = '23', '13', '08', '64', '62'
    '(' = '00', '1C', '22', '41', '00'
    ')' = '00', '41', '22', '1C', '00'
    ' ' = '00', '00', '00', '00', '00'
}

function Set-ScoutCanvasText {
    <#
    .SYNOPSIS
        Draw a string at (X, Y), scaled by whole pixels.
    #>
    param(
        $Canvas,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$X,
        [int]$Y,
        [string]$Hex = '1A1A1A',
        [int]$Scale = 2
    )
    if ([string]::IsNullOrEmpty($Text)) { return }
    # Validate the colour once here rather than letting a bad hex throw from inside the glyph
    # loop, where the error would name a rectangle rather than the label that caused it.
    $null = ConvertFrom-ScoutHex -Hex $Hex
    $cursor = $X
    foreach ($ch in $Text.ToUpperInvariant().ToCharArray()) {
        $key = [string]$ch
        $cols = if ($Script:ScoutGlyphs.ContainsKey($key)) { $Script:ScoutGlyphs[$key] } else { $Script:ScoutGlyphs[' '] }
        for ($c = 0; $c -lt 5; $c++) {
            $bits = [Convert]::ToInt32($cols[$c], 16)
            for ($r = 0; $r -lt 7; $r++) {
                if (($bits -shr $r) -band 1) {
                    # One filled rect per lit font pixel: at Scale 2 that is a 2x2 block, and the
                    # rect helper already clips, so a label running off the canvas edge truncates
                    # instead of throwing.
                    Set-ScoutCanvasRect -Canvas $Canvas -X ($cursor + $c * $Scale) -Y ($Y + $r * $Scale) `
                        -Width $Scale -Height $Scale -Hex $Hex
                }
            }
        }
        $cursor += 6 * $Scale
    }
}

function Get-ScoutTextWidth {
    [OutputType([int])]
    param([AllowEmptyString()][string]$Text, [int]$Scale = 2)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ($Text.Length * 6 * $Scale)
}

#endregion

#region Figures

# The chart palette measured under AB#6874. These are SERIES colours, deliberately not the
# document chrome — navy and steel failed the normal-vision distinguishability floor against
# each other and were the two most-used series colours in every chart Scout drew.
$Script:ScoutFigureStatusHex = @{
    Pass    = '0CA30C'
    Partial = 'FAB219'
    Fail    = 'D03B3B'
    Error   = 'EC835A'
    Manual  = '2A78D6'
    Unknown = '6E7079'
}
$Script:ScoutFigureInk = '1A1A1A'
$Script:ScoutFigureMuted = '595959'
$Script:ScoutFigureGrid = 'D9D9D9'
$Script:ScoutFigureSurface = 'FFFFFF'

function Get-ScoutFigureProp {
    param($Obj, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $Default }
}

function New-ScoutFigureAreaScores {
    <#
    .SYNOPSIS
        Horizontal bars — alignment score per assessed area, worst first.

    .DESCRIPTION
        Worst-first rather than alphabetical because the reader's question is "where is the
        problem", and a chart sorted by name makes them find it themselves. Every bar carries a
        direct value label in text ink rather than in the series colour — the relief rule from
        the AB#6874 palette validation, which is what keeps a sub-3:1 fill legible.
    #>
    param($Areas, [int]$Width = 900, [int]$RowHeight = 34)

    $rows = @(@($Areas) | Where-Object { $null -ne (Get-ScoutFigureProp $_ 'Score') } |
            Sort-Object @{ Expression = { [double](Get-ScoutFigureProp $_ 'Score' 0) } } |
            Select-Object -First 14)
    if ($rows.Count -eq 0) { return $null }

    $top = 44
    $height = $top + ($rows.Count * $RowHeight) + 20
    $canvas = New-ScoutCanvas -Width $Width -Height $height -BackgroundHex $Script:ScoutFigureSurface
    Set-ScoutCanvasText -Canvas $canvas -Text 'Alignment score by area' -X 16 -Y 14 -Hex $Script:ScoutFigureInk -Scale 2

    $labelWidth = 300
    $barLeft = $labelWidth + 16
    $barMax = $Width - $barLeft - 90

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $y = $top + ($i * $RowHeight)
        $score = [double](Get-ScoutFigureProp $r 'Score' 0)
        $label = "$(Get-ScoutFigureProp $r 'Area')"
        if ($label.Length -gt 24) { $label = $label.Substring(0, 24) }

        Set-ScoutCanvasText -Canvas $canvas -Text $label -X 16 -Y ($y + 6) -Hex $Script:ScoutFigureInk -Scale 2
        Set-ScoutCanvasRect -Canvas $canvas -X $barLeft -Y ($y + 4) -Width $barMax -Height 18 -Hex $Script:ScoutFigureGrid

        $fillHex = if ($score -ge 80) { $Script:ScoutFigureStatusHex.Pass }
        elseif ($score -ge 50) { $Script:ScoutFigureStatusHex.Partial }
        else { $Script:ScoutFigureStatusHex.Fail }
        $barLen = [int][Math]::Round($barMax * ([Math]::Max(0, [Math]::Min(100, $score)) / 100))
        Set-ScoutCanvasRect -Canvas $canvas -X $barLeft -Y ($y + 4) -Width $barLen -Height 18 -Hex $fillHex

        Set-ScoutCanvasText -Canvas $canvas -Text ("{0:N0}" -f $score) -X ($barLeft + $barMax + 12) -Y ($y + 6) -Hex $Script:ScoutFigureInk -Scale 2
    }

    return [pscustomobject]@{
        Name    = 'area-scores'
        Caption = 'Figure 1 — Alignment score by assessed area, worst first.'
        Width   = $Width
        Height  = $height
        Bytes   = (ConvertTo-ScoutPngBytes -Width $Width -Height $height -Pixels $canvas.Pixels)
    }
}

function New-ScoutFigureStatusComposition {
    <#
    .SYNOPSIS
        A single stacked bar — how the run's controls divide across the status states.

    .DESCRIPTION
        A stacked bar rather than a pie: the reader's question is proportion against a whole they
        already know the size of, and a pie makes small slices unreadable exactly where the
        interesting ones are. Not assessed gets its own segment (clause W-17) rather than being
        folded into failures.
    #>
    param($AllFindings, [int]$Width = 900, [int]$Height = 190)

    $findings = @($AllFindings)
    if ($findings.Count -eq 0) { return $null }

    $order = @('Pass', 'Partial', 'Fail', 'Error', 'Manual', 'Unknown')
    $counts = [ordered]@{}
    foreach ($k in $order) { $counts[$k] = 0 }
    foreach ($f in $findings) {
        $s = "$(Get-ScoutFigureProp $f 'Status')"
        if ($counts.Contains($s)) { $counts[$s]++ } else { $counts['Unknown']++ }
    }

    $canvas = New-ScoutCanvas -Width $Width -Height $Height -BackgroundHex $Script:ScoutFigureSurface
    Set-ScoutCanvasText -Canvas $canvas -Text 'Controls by status' -X 16 -Y 14 -Hex $Script:ScoutFigureInk -Scale 2

    $barLeft = 16
    $barWidth = $Width - 32
    $barTop = 50
    $barHeight = 40
    $total = $findings.Count
    $x = $barLeft
    foreach ($k in $order) {
        $n = $counts[$k]
        if ($n -le 0) { continue }
        $w = [int][Math]::Round($barWidth * ($n / $total))
        Set-ScoutCanvasRect -Canvas $canvas -X $x -Y $barTop -Width $w -Height $barHeight -Hex $Script:ScoutFigureStatusHex[$k]
        # A 2px surface-coloured ring between segments, so touching fills read as separate marks.
        Set-ScoutCanvasRect -Canvas $canvas -X ($x + $w - 2) -Y $barTop -Width 2 -Height $barHeight -Hex $Script:ScoutFigureSurface
        $x += $w
    }

    # Legend, with the count on every entry — a segment the reader cannot measure is decoration.
    $lx = $barLeft
    $ly = $barTop + $barHeight + 22
    foreach ($k in $order) {
        $n = $counts[$k]
        if ($n -le 0) { continue }
        $label = if ($k -eq 'Manual') { "NOT ASSESSED $n" } else { "$($k.ToUpperInvariant()) $n" }
        Set-ScoutCanvasRect -Canvas $canvas -X $lx -Y $ly -Width 14 -Height 14 -Hex $Script:ScoutFigureStatusHex[$k]
        Set-ScoutCanvasText -Canvas $canvas -Text $label -X ($lx + 20) -Y ($ly + 1) -Hex $Script:ScoutFigureMuted -Scale 2
        $lx += 20 + (Get-ScoutTextWidth -Text $label -Scale 2) + 24
    }

    return [pscustomobject]@{
        Name    = 'status-composition'
        Caption = 'Figure 2 — Every control evaluated in this run, by status. "Not assessed" is a state, not a failure.'
        Width   = $Width
        Height  = $Height
        Bytes   = (ConvertTo-ScoutPngBytes -Width $Width -Height $Height -Pixels $canvas.Pixels)
    }
}

function New-ScoutFigureSeverityHeatmap {
    <#
    .SYNOPSIS
        Area x severity heatmap of failing controls — where the risk is concentrated.
    #>
    param($AllFindings, [int]$Width = 900)

    $fails = @(@($AllFindings) | Where-Object { "$(Get-ScoutFigureProp $_ 'Status')" -eq 'Fail' })
    if ($fails.Count -eq 0) { return $null }

    $severities = @('high', 'medium', 'low')
    $areas = @($fails | ForEach-Object { "$(Get-ScoutFigureProp $_ 'Area')" } | Sort-Object -Unique | Select-Object -First 12)

    $cellW = 120
    $cellH = 36
    $left = 300
    $top = 76
    $height = $top + ($areas.Count * $cellH) + 20
    $canvas = New-ScoutCanvas -Width $Width -Height $height -BackgroundHex $Script:ScoutFigureSurface
    Set-ScoutCanvasText -Canvas $canvas -Text 'Failing controls by area and severity' -X 16 -Y 14 -Hex $Script:ScoutFigureInk -Scale 2

    for ($c = 0; $c -lt $severities.Count; $c++) {
        Set-ScoutCanvasText -Canvas $canvas -Text $severities[$c] -X ($left + $c * $cellW + 8) -Y ($top - 24) -Hex $Script:ScoutFigureMuted -Scale 2
    }

    # The scale is normalised to the busiest cell in THIS run, so the darkest cell always means
    # "the worst one here" rather than "past some absolute threshold nobody agreed".
    $matrix = @{}
    $peak = 1
    foreach ($a in $areas) {
        foreach ($s in $severities) {
            $n = @($fails | Where-Object {
                    "$(Get-ScoutFigureProp $_ 'Area')" -eq $a -and
                    "$(Get-ScoutFigureProp $_ 'Severity')".ToLowerInvariant() -eq $s
                }).Count
            $matrix["$a|$s"] = $n
            if ($n -gt $peak) { $peak = $n }
        }
    }

    for ($r = 0; $r -lt $areas.Count; $r++) {
        $a = $areas[$r]
        $y = $top + ($r * $cellH)
        $label = if ($a.Length -gt 24) { $a.Substring(0, 24) } else { $a }
        Set-ScoutCanvasText -Canvas $canvas -Text $label -X 16 -Y ($y + 10) -Hex $Script:ScoutFigureInk -Scale 2
        for ($c = 0; $c -lt $severities.Count; $c++) {
            $n = $matrix["$a|$($severities[$c])"]
            $x = $left + $c * $cellW
            $hex = if ($n -eq 0) { $Script:ScoutFigureGrid } else {
                $t = $n / $peak
                $base = ConvertFrom-ScoutHex -Hex $Script:ScoutFigureStatusHex.Fail
                # Blend towards the surface for lighter cells, so intensity reads as intensity.
                '{0:X2}{1:X2}{2:X2}' -f `
                ([int](255 - (255 - $base[0]) * $t)),
                ([int](255 - (255 - $base[1]) * $t)),
                ([int](255 - (255 - $base[2]) * $t))
            }
            Set-ScoutCanvasRect -Canvas $canvas -X $x -Y $y -Width ($cellW - 6) -Height ($cellH - 6) -Hex $hex
            # Direct value label on every cell — this is the relief rule again: the fill alone
            # cannot be read to a number, so the number is written on it.
            Set-ScoutCanvasText -Canvas $canvas -Text "$n" -X ($x + 8) -Y ($y + 8) -Hex $Script:ScoutFigureInk -Scale 2
        }
    }

    return [pscustomobject]@{
        Name    = 'severity-heatmap'
        Caption = 'Figure 3 — Failing controls by area and severity. Shading is relative to the busiest cell in this run.'
        Width   = $Width
        Height  = $height
        Bytes   = (ConvertTo-ScoutPngBytes -Width $Width -Height $height -Pixels $canvas.Pixels)
    }
}

function Export-ScoutFigureSet {
    <#
    .SYNOPSIS
        Render every report figure to PNG and return descriptors for the renderers to embed.

    .DESCRIPTION
        Clause D-02: a figure that fails to render is reported as a warning and OMITTED, never
        emitted broken or empty. Each figure is built inside its own try/catch for exactly that
        reason — one bad data shape must not cost the document the other two figures, and a
        zero-byte PNG in a Word package is a corrupt document rather than a missing picture.

        Clause D-01: each figure is written to disk as a PNG alongside whatever source form the
        diagram pipeline produced, so the rasterised output is a first-class artefact and not
        only an embedded blob.

    .OUTPUTS
        Descriptors with Name, Caption, Width, Height, Bytes and Path.
    #>
    param($Findings, [Parameter(Mandatory)][string]$OutputPath)

    $figDir = Join-Path $OutputPath 'figures'
    if (-not (Test-Path $figDir)) { New-Item -ItemType Directory -Path $figDir -Force | Out-Null }

    $areas = @(Get-ScoutFigureProp $Findings 'Areas')
    $all = @(Get-ScoutFigureProp $Findings 'Findings')

    $builders = @(
        @{ Name = 'area-scores'; Script = { New-ScoutFigureAreaScores -Areas $areas } }
        @{ Name = 'status-composition'; Script = { New-ScoutFigureStatusComposition -AllFindings $all } }
        @{ Name = 'severity-heatmap'; Script = { New-ScoutFigureSeverityHeatmap -AllFindings $all } }
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($b in $builders) {
        try {
            $fig = & $b.Script
            if ($null -eq $fig) { continue }
            $path = Join-Path $figDir "$($fig.Name).png"
            [System.IO.File]::WriteAllBytes($path, $fig.Bytes)
            $result.Add(([pscustomobject]@{
                        Name    = $fig.Name
                        Caption = $fig.Caption
                        Width   = $fig.Width
                        Height  = $fig.Height
                        Bytes   = $fig.Bytes
                        Path    = $path
                    }))
        }
        catch {
            Write-Warning "Export-ScoutFigureSet: figure '$($b.Name)' did not render ($($_.Exception.Message)) — omitted from this run's report."
        }
    }

    # Returned WITHOUT the usual unary comma. These are plain descriptors, not OpenXmlElements,
    # so there is nothing to protect from pipeline unrolling -- and returning the array as a
    # single object here made the caller's `@(...)` produce an array-of-one-array, which then
    # tried to embed all three figures as if they were one.
    return $result.ToArray()
}

#endregion
