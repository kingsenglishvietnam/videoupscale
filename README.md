# videoupscale

Upscale videos from PowerShell with Lanczos resizing plus CAS sharpening, losslessly by default.

No AI: every frame is resized on its own (Lanczos), then sharpened with AMD FidelityFX CAS to
offset the softness resizing adds. Output is 10-bit, which keeps the in-between values scaling
creates and resists banding in dark gradients. Audio is copied untouched.

Pairs with [videojoin](https://github.com/kingsenglishvietnam/videojoin): join your clips
losslessly, then upscale the joined file once.

## Requirements

- PowerShell 7+
- `ffmpeg` and `ffprobe` on `PATH`

## Usage

```powershell
.\videoupscale3.ps1                          # every video in the folder, 2x, lossless
.\videoupscale3.ps1 Genesis* -Quality Both   # lossless and upload versions in one go
.\videoupscale3.ps1 Genesis* -Quality Upload # compact upload file only
.\videoupscale3.ps1 clip.mp4 *.mov -Scale 3  # these files, 3x
.\videoupscale3.ps1 clip.mp4 -Sharpen 0      # pure Lanczos, no sharpening
```

| Parameter | Default | Meaning |
|---|---|---|
| *(files)* | every video in the folder | Names, paths or wildcards |
| `-Path` | current folder | Folder to look in; base for relative names |
| `-Scale` | `2` | Upscale factor (fractions allowed; dimensions kept even) |
| `-Sharpen` | `0.4` | CAS strength 0-1; `0` = off |
| `-Quality` | `Lossless` | `Lossless`, `Upload` (compact, CRF `-Crf`) or `Both` |
| `-Crf` | `16` | x264 quality of the Upload version |
| `-Force` | off | Overwrite existing outputs |

Output goes next to the source, where N is the new short side (720x1280 at 2x -> 1440):
lossless as `<name>_<N>p.mp4`, upload as `<name>_<N>p_crf<n>.mp4`, so both can coexist.
Outputs are never upscaled again by a later run.

## Why upscale before uploading?

Platforms such as YouTube encode higher-resolution uploads at higher bitrates, so a 720p
video upscaled to 1440p often looks better after the platform's own compression than the
720p original would.

## Per-frame vs AI upscalers

Because this tool treats every frame independently, it gives the same result whether you
upscale clips before joining or the joined video afterwards; afterwards is simply one pass.
AI / temporal upscalers are different: run those on each clip **before** joining, since
crossfades mix two scenes and can confuse them.

## Notes

- Lossless output (CRF 0) uses x264's High 4:4:4 Predictive profile: VLC, ffplay, editors and
  YouTube handle it; most built-in players (Windows Films & TV, QuickTime, phones) do not.
  `-Quality Upload` output (High 10) plays more widely.
- If the source audio can't be stored in MP4 unchanged (e.g. PCM from a `.mov`), it is encoded
  to FLAC instead, which is still lossless.
- Colour tags are copied from the source; other metadata (titles, comments) is not.

## Licence

[AGPL-3.0](LICENSE)
