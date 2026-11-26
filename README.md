# videoupscale

Upscale videos with Lanczos resizing and CAS sharpening, from PowerShell, into ready-made
presets for archiving, computers and phones.

Each frame is resized with Lanczos, then sharpened with AMD FidelityFX CAS to offset the
softness resizing adds. No AI is involved, so nothing is invented.

Companion to [videojoin](https://github.com/kingsenglishvietnam/videojoin): join clips
losslessly, then upscale the result once.

## Requirements

- PowerShell 7+
- `ffmpeg` and `ffprobe` on `PATH`

## Usage

Scripts are versioned (`videoupscale1.ps1`, `videoupscale2.ps1`, ...); use the highest number.

```powershell
.\videoupscale4.ps1 final.mp4                             # Archive + Computer (default)
.\videoupscale4.ps1 final.mp4 -Quality Mobile             # phone version only
.\videoupscale4.ps1 final.mp4 -Quality All                # Archive, Computer and Mobile
.\videoupscale4.ps1 final.mp4 -Quality Computer,Mobile    # any combination
.\videoupscale4.ps1 *.mov -Scale 3 -Sharpen 0             # 3x, no sharpening
```

## Presets

Choose one or several with `-Quality`. `N` is the output's short side (720x1280 at 2x gives 1440).

| Preset | Made for | Video | Audio (`auto`) | File | Example: 17.5 s |
|---|---|---|---|---|---|
| **Archive** | Editing, YouTube | Lossless, 10-bit, at `-Scale` | Copy, else FLAC | `<name>_<N>p.mp4` | 177 MB |
| **Computer** | Local playback, sites and apps | 8-bit H.264 High, CRF 16, at `-Scale` | Copy, else FLAC | `<name>_<N>p_computer.mp4` | ~37 MB |
| **Mobile** | Phones, low bandwidth | 8-bit H.264 High, CRF 18, 1080 short side | Copy AAC, else AAC 256k | `<name>_<N>p_mobile.mp4` | smaller |
| Compact | Smaller YouTube upload | 10-bit H.264 High 10, CRF 16, at `-Scale` | Copy, else FLAC | `<name>_<N>p_crf16.mp4` | 23 MB |

`All` means Archive + Computer + Mobile. The default is Archive + Computer.

Why upload the Archive file to YouTube? YouTube re-encodes everything, so a lossless upload
gives its encoder the best possible starting point. Use Compact only when the lossless file is
too big to upload comfortably.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| *(files)* | every video in the folder | Names, paths or wildcards |
| `-Path` | current folder | Folder to search; base for relative names |
| `-Quality` | `Archive,Computer` | One or more of `Archive`, `Computer`, `Mobile`, `Compact`, `All` |
| `-Scale` | `2` | Upscale factor for Archive, Computer and Compact; fractions allowed |
| `-MobileSize` | `1080` | Short side of the Mobile output |
| `-Sharpen` | `0.4` | CAS strength, `0`-`1`; `0` turns it off |
| `-Crf` | `16` | CRF for Computer and Compact |
| `-MobileCrf` | `18` | CRF for Mobile |
| `-Audio` | `auto` | `auto`, `copy`, `flac`, `alac`, `aac`, `opus` or `mp3` |
| `-AudioBitrate` | per codec | For `aac` (512k), `opus` (510k), `mp3` (320k), e.g. `256k` |
| `-Force` | off | Overwrite existing outputs |

## Audio

| `-Audio` | Result | Lossless? |
|---|---|---|
| `auto` | Copy the source audio when MP4 can hold it unchanged; otherwise FLAC (Mobile: AAC 256k) | Copy and FLAC are |
| `copy` | Source audio unchanged; fails if MP4 can't hold it | Yes |
| `flac` | FLAC, 24-bit | Yes |
| `alac` | Apple Lossless, 24-bit | Yes |
| `aac` | AAC-LC, 512k by default | No |
| `opus` | Opus, 510k by default | No |
| `mp3` | MP3, 320k by default | No |

Copying is always best when possible: it is the source audio, bit for bit.

For AAC, 48 kHz stereo has a format ceiling of about 576k, and every encoder tested (ffmpeg,
FDK-AAC, Nero) capped there whatever was requested. ffmpeg's built-in encoder spends only what
the sound needs, so 512k means "never limited" rather than "always 512k". On a 128k AAC source
it settles around 287k, and in our comparison it measured closer to the source than FDK-AAC or
Nero at 512-576k.

## Choosing files with wildcards

Any argument can be a wildcard, and you can give as many as you like. The script expands
them itself, so they need no quoting.

```powershell
.\videoupscale4.ps1 *.mp4                        # every MP4 in the folder
.\videoupscale4.ps1 *.mp4 *.mov                  # MP4s and MOVs
.\videoupscale4.ps1 trailer*                     # everything starting with "trailer"
.\videoupscale4.ps1 *final*                      # anything with "final" in the name
.\videoupscale4.ps1 scene?.mp4                   # scene1.mp4 ... scene9.mp4 (? = one character)
.\videoupscale4.ps1 scene[1-3].mp4               # scene1, scene2, scene3 only
.\videoupscale4.ps1 ep[0-9][0-9]*                # ep01..., ep02..., ep10..., any two digits
.\videoupscale4.ps1 D:\Exports\*.mov             # wildcards in other folders too
.\videoupscale4.ps1 intro.mp4 ep*.mp4 outro.mp4  # mix exact names and patterns
```

| Pattern | Matches |
|---|---|
| `*` | any run of characters, including none |
| `?` | exactly one character |
| `[abc]` | one of the listed characters |
| `[1-3]` | one character in the range |

Things handled for you:

- **Outputs are skipped.** `*.mp4` won't re-upscale `video_1440p.mp4`, `video_1440p_computer.mp4`
  or any other earlier output, so you can rerun the same command safely.
- **No duplicates.** A file matched by two patterns is processed once.
- **Only videos.** Wildcards pick up `.mp4 .m4v .mov .mkv .webm` and ignore everything else.
- **Exact names win.** A file whose real name contains `[` or `]` is still found when you
  type its full name.
- **Typos are reported.** A pattern that matches nothing prints a warning instead of failing
  silently.

## Playback

| Preset | Plays on |
|---|---|
| Computer, Mobile | Everything: phones, browsers, TVs, built-in players |
| Archive, Compact | VLC, ffplay, video editors, YouTube. Not most phones, browsers or built-in players |

Archive uses x264's High 4:4:4 Predictive profile (lossless); Compact uses 10-bit H.264 (High 10).

## Per-frame vs AI upscaling

This tool treats every frame independently, so upscaling clips before joining and upscaling
the joined video give the same result; afterwards is just one pass instead of many.
AI or temporal upscalers are different: run those on each clip before joining, because a
crossfade blends two scenes and can confuse them.

## Notes

- Colour tags are copied from the source; titles, comments and other metadata are not.
- Older preset names still work: `Lossless` = Archive, `Upload` = Compact, `Both` = Archive + Compact.

## Licence

[AGPL-3.0](LICENSE)
