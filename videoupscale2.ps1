<#
.SYNOPSIS
    videoupscale2.ps1 - upscale videos with Lanczos + CAS sharpening, losslessly by default.

.DESCRIPTION
    Per-frame upscale (no AI): Lanczos resize by -Scale, then AMD FidelityFX CAS sharpening
    to offset the softness resizing adds. Output is 10-bit, which holds the in-between
    values scaling creates and resists banding in dark gradients.

    Which files:
      - No arguments: every video in -Path.
      - Arguments: only those - file names, paths or wildcards (e.g. Genesis*).
        Relative names resolve against -Path.
      Its own outputs (_1440p, _1440p_crf16, ...) are never upscaled again.

    Output, next to the source, N = new short side (720x1280 at 2x -> 1440):
      lossless (CRF 0)   <name>_<N>p.mp4
      CRF n              <name>_<N>p_crf<n>.mp4
    so lossless and compact versions can sit side by side. -Crf takes several values to
    make several versions in one run (-Crf 0,16). Existing outputs are skipped unless -Force.

    Changes since v1:
      - No arguments = every video in the folder (v1 only looked for joined_* files).
      - CRF outputs get a _crf<n> suffix, so they no longer overwrite the lossless file.
      - -Crf accepts several values: -Crf 0,16 makes both versions in one run.

    Video: x264, 10-bit 4:2:0. Default CRF 0 = lossless (large: High 4:4:4 Predictive
    profile, plays in VLC/ffplay/editors/YouTube, not in most built-in players).
    -Crf 16 gives a compact, high-quality upload file (High 10 profile).
    Audio: copied unchanged. If the source audio can't go into MP4 as-is (e.g. PCM from
    a .mov), it is encoded to FLAC instead - still lossless.
    Colour tags are copied from the source; other metadata is not.

.PARAMETER Files
    Optional. Files to upscale: names, paths or wildcards. Positional; several allowed.
.PARAMETER Path
    Folder used when no files are given, and base for relative names. Default: current folder.
.PARAMETER Scale
    Upscale factor. Default 2. Fractions allowed (1.5); dimensions are kept even.
.PARAMETER Sharpen
    CAS strength 0-1. Default 0.4. 0 = pure Lanczos, no sharpening.
.PARAMETER Crf
    0 (default) = lossless. 16 is a good compact upload setting. Several values allowed
    (-Crf 0,16) to make several versions in one run.
.PARAMETER Force
    Overwrite existing outputs.

.EXAMPLE
    .\videoupscale2.ps1                         # every video in the folder, 2x, lossless
.EXAMPLE
    .\videoupscale2.ps1 Genesis* -Crf 0,16      # lossless and compact versions in one go
.EXAMPLE
    .\videoupscale2.ps1 clip.mp4 -Scale 3 -Sharpen 0
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Files,
    [string]$Path = '.',
    [ValidateRange(1.01, 8)][double]$Scale = 2,
    [ValidateRange(0, 1)][double]$Sharpen = 0.4,
    [ValidateRange(0, 51)][int[]]$Crf = @(0),
    [switch]$Force
)

$videoExt = '.mp4', '.m4v', '.mov', '.mkv', '.webm'
$ownOut   = '_\d{3,5}p(_crf\d+)?$'   # our outputs, matched against BaseName
$inv      = [Globalization.CultureInfo]::InvariantCulture

foreach ($t in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t not found on PATH" }
}
$Path = (Resolve-Path -LiteralPath $Path).Path

# --- file selection --------------------------------------------------------
$sources = [Collections.Generic.List[IO.FileInfo]]::new()
if (-not $Files) {
    Get-ChildItem -LiteralPath $Path -File |
        Where-Object { $_.Extension.ToLower() -in $videoExt -and $_.BaseName -notmatch $ownOut } |
        Sort-Object Name |
        ForEach-Object { $sources.Add($_) }
} else {
    $seen = @{}
    foreach ($item in $Files) {
        $full = if ([IO.Path]::IsPathRooted($item)) { $item } else { Join-Path $Path $item }
        $found = if (Test-Path -LiteralPath $full -PathType Leaf) {
            @(Get-Item -LiteralPath $full)
        } else {
            @(Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension.ToLower() -in $videoExt })
        }
        if ($found.Count -eq 0) { Write-Warning "no video files match: $item"; continue }
        foreach ($f in $found) {
            if ($f.BaseName -match $ownOut) { Write-Host "skip (already an upscale): $($f.Name)"; continue }
            if ($seen.ContainsKey($f.FullName)) { continue }
            $seen[$f.FullName] = $true
            $sources.Add($f)
        }
    }
}
if ($sources.Count -eq 0) { Write-Host 'Nothing to upscale.'; return }
$Crf = @($Crf | Select-Object -Unique)

# --- helpers ---------------------------------------------------------------
function Get-VideoInfo([string]$File) {
    $j = & ffprobe -v error -select_streams v:0 `
        -show_entries stream=width,height,color_space,color_primaries,color_transfer,color_range `
        -of json $File | Out-String | ConvertFrom-Json
    $s = $j.streams | Select-Object -First 1
    $cmap = [ordered]@{ color_space = '-colorspace'; color_primaries = '-color_primaries'; color_transfer = '-color_trc'; color_range = '-color_range' }
    $colorArgs = @()
    foreach ($k in $cmap.Keys) {
        $v = $s.$k
        if ($v -and $v -notin 'unknown', 'reserved', 'unspecified') { $colorArgs += $cmap[$k], $v }
    }
    [pscustomobject]@{ Width = [int]$s.width; Height = [int]$s.height; ColorArgs = $colorArgs }
}

function Get-EncArgs([int]$Q) {
    if ($Q -eq 0) {
        @('-c:v', 'libx264', '-preset', 'slow', '-crf', '0', '-pix_fmt', 'yuv420p10le')
    } else {
        @('-c:v', 'libx264', '-preset', 'slow', '-crf', "$Q", '-tune', 'film',
          '-x264-params', 'aq-mode=3', '-pix_fmt', 'yuv420p10le')
    }
}
$sStr = $Scale.ToString($inv)
$vf = "scale=w='trunc(iw*$sStr/2)*2':h='trunc(ih*$sStr/2)*2':flags=lanczos+accurate_rnd+full_chroma_int"
if ($Sharpen -gt 0) { $vf += ",cas=strength=$($Sharpen.ToString($inv))" }

# --- main ------------------------------------------------------------------
$results = foreach ($src in $sources) {
    $info = Get-VideoInfo $src.FullName
    $nw = [math]::Floor($info.Width * $Scale / 2) * 2
    $nh = [math]::Floor($info.Height * $Scale / 2) * 2
    $tag = "$([math]::Min($nw, $nh))p"
    $sharp = if ($Sharpen -gt 0) { "CAS $Sharpen" } else { 'no sharpening' }
    Write-Host "`n== $($src.Name)"

    foreach ($q in $Crf) {
        $suffix = if ($q -eq 0) { "_$tag" } else { "_${tag}_crf$q" }
        $out = Join-Path $src.DirectoryName "$($src.BaseName)$suffix.mp4"
        $mode = if ($q -eq 0) { 'lossless' } else { "CRF $q" }

        if ((Test-Path -LiteralPath $out) -and -not $Force) {
            Write-Host "  skip (exists): $(Split-Path $out -Leaf)  (-Force to redo)"
            continue
        }
        Write-Host "  $($info.Width)x$($info.Height) -> ${nw}x${nh}  (Lanczos x$sStr, $sharp, 10-bit, $mode)"
        $enc = Get-EncArgs $q

        $done = $false
        foreach ($audio in @(@('-c:a', 'copy'), @('-c:a', 'flac', '-sample_fmt', 's32', '-bits_per_raw_sample', '24'))) {
            & ffmpeg -hide_banner -loglevel error -stats -y `
                -i $src.FullName `
                -map 0:v:0 -map '0:a?' `
                -vf $vf `
                -map_metadata -1 `
                @enc @($info.ColorArgs) `
                @audio `
                -movflags +faststart `
                $out
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) { $done = $true; break }
            if ($audio[1] -eq 'copy') { Write-Host '  audio copy into MP4 failed, retrying with FLAC (lossless)' }
        }
        if (-not $done) {
            Write-Warning "ffmpeg failed: $($src.Name) ($mode)"
            Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
            continue
        }
        $o = Get-Item -LiteralPath $out
        Write-Host ("  [OK] -> {0}  ({1:0.0} MB)" -f $o.Name, ($o.Length / 1MB))
        [pscustomobject]@{
            Output = $o.Name
            From   = "$($info.Width)x$($info.Height)"
            To     = "${nw}x${nh}"
            Mode   = $mode
            SrcMB  = [math]::Round($src.Length / 1MB, 1)
            OutMB  = [math]::Round($o.Length / 1MB, 1)
        }
    }
}
if ($results) { Write-Host ''; $results | Format-Table -AutoSize }
