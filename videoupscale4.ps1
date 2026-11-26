<#
.SYNOPSIS
    videoupscale4.ps1 - upscale videos with Lanczos + CAS sharpening into purpose-built presets.

.DESCRIPTION
    Each frame is resized with Lanczos, then sharpened with AMD FidelityFX CAS to offset the
    softness resizing adds. No AI: nothing is invented.

    Presets (-Quality; choose one or several, default Archive + Computer):

      Archive   Lossless x264, 10-bit, at -Scale        -> <name>_<N>p.mp4
                For editing and for uploading to YouTube (best possible source for its encoder).
      Computer  8-bit H.264 High, CRF -Crf (16), at -Scale  -> <name>_<N>p_computer.mp4
                Plays everywhere: local playback, Zalo, other sites and apps.
      Mobile    8-bit H.264 High, CRF -MobileCrf (18), short side -MobileSize (1080)
                                                         -> <name>_<N>p_mobile.mp4
                Phones and low bandwidth.
      Compact   10-bit H.264 High 10, CRF -Crf (16), at -Scale -> <name>_<N>p_crf<n>.mp4
                Small YouTube upload when Archive is too big. Doesn't play everywhere.
      All       Archive + Computer + Mobile.

    N is the output's short side (720x1280 at 2x -> 1440).

    Audio (-Audio, default auto):
      auto   Archive/Computer/Compact: copy the source audio if MP4 can hold it unchanged
             (AAC, FLAC, ALAC, MP3, Opus), otherwise FLAC 24-bit.
             Mobile: copy if the source is AAC, otherwise AAC 256k.
      copy   Always copy unchanged (fails if MP4 can't hold the source codec).
      flac   Lossless 24-bit. Accepted by Zalo stories and posts.
      alac   Lossless 24-bit, Apple-friendly.
      aac    ffmpeg native AAC, default 512k (best measured on 48 kHz stereo; it spends what
             the sound needs, about 287k on Veo/Gemini audio).
      opus   default 510k.
      mp3    default 320k.
    -AudioBitrate overrides the aac/opus/mp3 default (e.g. -AudioBitrate 256k).

    Which files:
      - No arguments: every video in -Path.
      - Arguments: names, paths or wildcards (e.g. Genesis*). Relative names resolve against -Path.
      Its own outputs are never upscaled again. Existing outputs are skipped unless -Force.

    Colour tags are copied from the source; other metadata is not.

    Changes since v3:
      - Presets renamed and extended: Archive (was Lossless), Computer (new, 8-bit 1440p),
        Mobile (new, 8-bit 1080p), Compact (was Upload). Several at once; default Archive+Computer.
      - -Audio auto|copy|flac|alac|aac|opus|mp3 and -AudioBitrate.
      - Old names still accepted: Lossless = Archive, Upload = Compact, Both = Archive + Compact.

.PARAMETER Files
    Optional. Files to upscale: names, paths or wildcards. Positional; several allowed.
.PARAMETER Path
    Folder used when no files are given, and base for relative names. Default: current folder.
.PARAMETER Quality
    One or more of Archive, Computer, Mobile, Compact, All. Default: Archive, Computer.
.PARAMETER Scale
    Upscale factor for Archive, Computer and Compact. Default 2. Fractions allowed.
.PARAMETER MobileSize
    Short side of the Mobile output in pixels. Default 1080.
.PARAMETER Sharpen
    CAS strength 0-1. Default 0.4. 0 = pure Lanczos.
.PARAMETER Crf
    CRF for Computer and Compact. Default 16.
.PARAMETER MobileCrf
    CRF for Mobile. Default 18.
.PARAMETER Audio
    auto (default), copy, flac, alac, aac, opus or mp3.
.PARAMETER AudioBitrate
    Bitrate for aac/opus/mp3, e.g. 256k. Defaults: aac 512k, opus 510k, mp3 320k.
.PARAMETER Force
    Overwrite existing outputs.

.EXAMPLE
    .\videoupscale4.ps1 Genesis*                         # Archive + Computer
.EXAMPLE
    .\videoupscale4.ps1 Genesis* -Quality Mobile          # phone version only
.EXAMPLE
    .\videoupscale4.ps1 Genesis* -Quality All             # all three
.EXAMPLE
    .\videoupscale4.ps1 clip.mp4 -Quality Computer,Mobile -Audio aac -AudioBitrate 320k
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Files,
    [string]$Path = '.',
    [ValidateSet('Archive', 'Computer', 'Mobile', 'Compact', 'All', 'Lossless', 'Upload', 'Both')]
    [string[]]$Quality = @('Archive', 'Computer'),
    [ValidateRange(1.01, 8)][double]$Scale = 2,
    [ValidateRange(240, 4320)][int]$MobileSize = 1080,
    [ValidateRange(0, 1)][double]$Sharpen = 0.4,
    [ValidateRange(1, 51)][int]$Crf = 16,
    [ValidateRange(1, 51)][int]$MobileCrf = 18,
    [ValidateSet('auto', 'copy', 'flac', 'alac', 'aac', 'opus', 'mp3')][string]$Audio = 'auto',
    [ValidatePattern('^\d+k?$')][string]$AudioBitrate,
    [switch]$Force
)

$videoExt = '.mp4', '.m4v', '.mov', '.mkv', '.webm'
$ownOut   = '_\d{3,5}p(_crf\d+|_computer|_mobile)?$'   # our outputs, matched against BaseName
$inv      = [Globalization.CultureInfo]::InvariantCulture
$mp4Safe  = 'aac', 'flac', 'alac', 'mp3', 'opus'     # audio codecs MP4 can hold unchanged

foreach ($t in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t not found on PATH" }
}
$Path = (Resolve-Path -LiteralPath $Path).Path

# --- presets ---------------------------------------------------------------
$order = 'Archive', 'Computer', 'Mobile', 'Compact'
$want = @{}
foreach ($q in $Quality) {
    switch ($q) {
        'All'      { $want.Archive = $true; $want.Computer = $true; $want.Mobile = $true }
        'Lossless' { $want.Archive = $true }
        'Upload'   { $want.Compact = $true }
        'Both'     { $want.Archive = $true; $want.Compact = $true }
        default    { $want[$q] = $true }
    }
}
$presets = @($order | Where-Object { $want[$_] })

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

# --- helpers ---------------------------------------------------------------
function Get-MediaInfo([string]$File) {
    $j = & ffprobe -v error `
        -show_entries stream=codec_type,codec_name,width,height,color_space,color_primaries,color_transfer,color_range `
        -of json $File | Out-String | ConvertFrom-Json
    $v = $j.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
    $a = $j.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1
    $cmap = [ordered]@{ color_space = '-colorspace'; color_primaries = '-color_primaries'; color_transfer = '-color_trc'; color_range = '-color_range' }
    $colorArgs = @()
    foreach ($k in $cmap.Keys) {
        $val = $v.$k
        if ($val -and $val -notin 'unknown', 'reserved', 'unspecified') { $colorArgs += $cmap[$k], $val }
    }
    [pscustomobject]@{
        Width      = [int]$v.width
        Height     = [int]$v.height
        ColorArgs  = $colorArgs
        AudioCodec = if ($a) { [string]$a.codec_name } else { $null }
    }
}

function Get-VideoArgs([string]$Preset) {
    switch ($Preset) {
        'Archive'  { @('-c:v', 'libx264', '-preset', 'slow', '-crf', '0', '-pix_fmt', 'yuv420p10le') }
        'Compact'  { @('-c:v', 'libx264', '-preset', 'slow', '-crf', "$Crf", '-tune', 'film',
                       '-x264-params', 'aq-mode=3', '-pix_fmt', 'yuv420p10le') }
        'Computer' { @('-c:v', 'libx264', '-preset', 'slow', '-crf', "$Crf", '-tune', 'film',
                       '-x264-params', 'aq-mode=3', '-profile:v', 'high', '-pix_fmt', 'yuv420p') }
        'Mobile'   { @('-c:v', 'libx264', '-preset', 'slow', '-crf', "$MobileCrf", '-tune', 'film',
                       '-x264-params', 'aq-mode=3', '-profile:v', 'high', '-pix_fmt', 'yuv420p') }
    }
}

function Get-AudioArgs([string]$Kind) {
    switch ($Kind) {
        'copy' { @('-c:a', 'copy') }
        'flac' { @('-c:a', 'flac', '-sample_fmt', 's32', '-bits_per_raw_sample', '24') }
        'alac' { @('-c:a', 'alac', '-sample_fmt', 's32p', '-bits_per_raw_sample', '24') }
        'aac'  { @('-c:a', 'aac', '-b:a', $(if ($AudioBitrate) { $AudioBitrate } else { '512k' })) }
        'aac256' { @('-c:a', 'aac', '-b:a', $(if ($AudioBitrate) { $AudioBitrate } else { '256k' })) }
        'opus' { @('-c:a', 'libopus', '-b:a', $(if ($AudioBitrate) { $AudioBitrate } else { '510k' })) }
        'mp3'  { @('-c:a', 'libmp3lame', '-b:a', $(if ($AudioBitrate) { $AudioBitrate } else { '320k' })) }
    }
}

function Get-AudioPlan([string]$Preset, [string]$SrcCodec) {
    # Returns attempts in order: each @{ Kind; Label }
    if (-not $SrcCodec) { return @(@{ Kind = 'none'; Label = 'no audio' }) }
    if ($Audio -ne 'auto') {
        return @(@{ Kind = $Audio; Label = $Audio })
    }
    if ($Preset -eq 'Mobile') {
        if ($SrcCodec -eq 'aac') {
            return @(@{ Kind = 'copy'; Label = 'copy (aac)' }, @{ Kind = 'aac256'; Label = 'aac' })
        }
        return @(@{ Kind = 'aac256'; Label = 'aac' })
    }
    if ($SrcCodec -in $mp4Safe) {
        return @(@{ Kind = 'copy'; Label = "copy ($SrcCodec)" }, @{ Kind = 'flac'; Label = 'flac' })
    }
    @(@{ Kind = 'flac'; Label = 'flac' })
}

function Get-Size([int]$W, [int]$H, [string]$Preset) {
    if ($Preset -eq 'Mobile') {
        $f = $MobileSize / [math]::Min($W, $H)
    } else {
        $f = $Scale
    }
    $nw = [math]::Floor($W * $f / 2) * 2
    $nh = [math]::Floor($H * $f / 2) * 2
    [pscustomobject]@{ W = $nw; H = $nh; Tag = "$([math]::Min($nw, $nh))p" }
}

# --- main ------------------------------------------------------------------
$sharp = if ($Sharpen -gt 0) { "CAS $Sharpen" } else { 'no sharpening' }
$results = foreach ($src in $sources) {
    $info = Get-MediaInfo $src.FullName
    Write-Host "`n== $($src.Name)  ($($info.Width)x$($info.Height), audio: $(if ($info.AudioCodec) { $info.AudioCodec } else { 'none' }))"

    foreach ($p in $presets) {
        $size = Get-Size $info.Width $info.Height $p
        $suffix = switch ($p) {
            'Archive'  { "_$($size.Tag)" }
            'Computer' { "_$($size.Tag)_computer" }
            'Mobile'   { "_$($size.Tag)_mobile" }
            'Compact'  { "_$($size.Tag)_crf$Crf" }
        }
        $out = Join-Path $src.DirectoryName "$($src.BaseName)$suffix.mp4"
        if ((Test-Path -LiteralPath $out) -and -not $Force) {
            Write-Host "  skip (exists): $(Split-Path $out -Leaf)  (-Force to redo)"
            continue
        }

        $vdesc = switch ($p) {
            'Archive'  { 'lossless 10-bit' }
            'Compact'  { "CRF $Crf 10-bit" }
            'Computer' { "CRF $Crf 8-bit" }
            'Mobile'   { "CRF $MobileCrf 8-bit" }
        }
        $vf = "scale=$($size.W):$($size.H):flags=lanczos+accurate_rnd+full_chroma_int"
        if ($Sharpen -gt 0) { $vf += ",cas=strength=$($Sharpen.ToString($inv))" }
        $videoArgs = Get-VideoArgs $p

        Write-Host "  [$p] -> $($size.W)x$($size.H)  ($vdesc, $sharp)"

        $done = $false; $usedAudio = ''
        $plan = @(Get-AudioPlan $p $info.AudioCodec)
        for ($i = 0; $i -lt $plan.Count; $i++) {
            $att = $plan[$i]
            $audioArgs = if ($att.Kind -eq 'none') { @('-an') } else { @(Get-AudioArgs $att.Kind) }
            & ffmpeg -hide_banner -loglevel error -stats -y `
                -i $src.FullName `
                -map 0:v:0 -map '0:a?' `
                -vf $vf `
                -map_metadata -1 `
                @videoArgs @($info.ColorArgs) `
                @audioArgs `
                -movflags +faststart `
                $out
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) { $done = $true; $usedAudio = $att.Label; break }
            if ($i -lt $plan.Count - 1) {
                Write-Host "  audio '$($att.Label)' failed, retrying with '$($plan[$i + 1].Label)'"
            }
        }
        if (-not $done) {
            Write-Warning "ffmpeg failed: $($src.Name) [$p]"
            Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
            continue
        }
        $o = Get-Item -LiteralPath $out
        Write-Host ("  [OK] -> {0}  ({1:0.0} MB)" -f $o.Name, ($o.Length / 1MB))
        [pscustomobject]@{
            Output = $o.Name
            Preset = $p
            Size   = "$($size.W)x$($size.H)"
            Video  = $vdesc
            Audio  = $usedAudio
            OutMB  = [math]::Round($o.Length / 1MB, 1)
        }
    }
}
if ($results) { Write-Host ''; $results | Format-Table -AutoSize }
