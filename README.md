# videoupscale

Upscale videos with Lanczos resizing and CAS sharpening, from PowerShell.

Each frame is resized with Lanczos, then sharpened with AMD FidelityFX CAS to offset the
softness resizing adds. No AI is involved, so nothing is invented. Output is 10-bit, which
keeps the in-between values scaling creates and resists banding in dark gradients. Audio is
copied unchanged.

Companion to [videojoin](https://github.com/kingsenglishvietnam/videojoin): join clips
losslessly, then upscale the result once.

## Requirements

- PowerShell 7+
- `ffmpeg` and `ffprobe` on `PATH`

## Usage

Scripts are versioned (`videoupscale1.ps1`, `videoupscale2.ps1`, ...); use the highest number.

```powershell
.\videoupscale3.ps1                              # every video in the folder: 2x, lossless
.\videoupscale3.ps1 final.mp4 -Quality Both      # lossless master and upload file
.\videoupscale3.ps1 final.mp4 -Quality Upload    # upload file only
.\videoupscale3.ps1 *.mov -Scale 3 -Sharpen 0    # 3x, no sharpening
```

| Parameter | Default | Meaning |
|---|---|---|
| *(files)* | every video in the folder | Names, paths or wildcards |
| `-Path` | current folder | Folder to search; base for relative names |
| `-Scale` | `2` | Upscale factor; fractions allowed |
| `-Sharpen` | `0.4` | CAS strength, `0`-`1`; `0` turns it off |
| `-Quality` | `Lossless` | `Lossless`, `Upload` or `Both` |
| `-Crf` | `16` | x264 CRF of the Upload version |
| `-Force` | off | Overwrite existing outputs |

## Choosing files with wildcards

Any argument can be a wildcard, and you can give as many as you like. The script expands
them itself, so they need no quoting.

```powershell
.\videoupscale3.ps1 *.mp4                        # every MP4 in the folder
.\videoupscale3.ps1 *.mp4 *.mov                  # MP4s and MOVs
.\videoupscale3.ps1 trailer*                     # everything starting with "trailer"
.\videoupscale3.ps1 *final*                      # anything with "final" in the name
.\videoupscale3.ps1 scene?.mp4                   # scene1.mp4 ... scene9.mp4 (? = one character)
.\videoupscale3.ps1 scene[1-3].mp4               # scene1, scene2, scene3 only
.\videoupscale3.ps1 ep[0-9][0-9]*                # ep01..., ep02..., ep10..., any two digits
.\videoupscale3.ps1 D:\Exports\*.mov             # wildcards in other folders too
.\videoupscale3.ps1 intro.mp4 ep*.mp4 outro.mp4  # mix exact names and patterns
```

| Pattern | Matches |
|---|---|
| `*` | any run of characters, including none |
| `?` | exactly one character |
| `[abc]` | one of the listed characters |
| `[1-3]` | one character in the range |

Things handled for you:

- **Outputs are skipped.** `*.mp4` won't re-upscale `video_1440p.mp4` or `video_1440p_crf16.mp4`
  from an earlier run, so you can rerun the same command safely.
- **No duplicates.** A file matched by two patterns is processed once.
- **Only videos.** Wildcards pick up `.mp4 .m4v .mov .mkv .webm` and ignore everything else.
- **Exact names win.** A file whose real name contains `[` or `]` is still found when you
  type its full name.
- **Typos are reported.** A pattern that matches nothing prints a warning instead of failing
  silently.

## Output

Files are written next to the source. `N` is the new short side (720x1280 at 2x gives 1440).

| Quality | File | Use | Example: 17.5 s, 1440x2560 |
|---|---|---|---|
| Lossless | `<name>_<N>p.mp4` | Archive, editing, upload | 177 MB |
| Upload | `<name>_<N>p_crf16.mp4` | Upload | 23 MB |

Existing outputs are skipped, and outputs are never upscaled again by a later run.

## Why upscale before uploading?

Platforms such as YouTube encode higher-resolution uploads at higher bitrates. A 720p video
upscaled to 1440p usually survives the platform's compression better than the 720p original.

## Per-frame vs AI upscaling

This tool treats every frame independently, so upscaling clips before joining and upscaling
the joined video give the same result; afterwards is just one pass instead of many.
AI or temporal upscalers are different: run those on each clip before joining, because a
crossfade blends two scenes and can confuse them.

## Playback

Both outputs are made for editing and uploading, not for playing on every device:

- Lossless uses x264's High 4:4:4 Predictive profile.
- Upload uses 10-bit H.264 (High 10).

VLC, ffplay, video editors and YouTube handle both. Many phones, browsers and built-in players
(Windows Films & TV, QuickTime) do not.

## Notes

- If the source audio can't go into MP4 unchanged (for example PCM from a `.mov`), it is
  converted to FLAC, which is still lossless.
- Colour tags are copied from the source; titles, comments and other metadata are not.

## Licence

[AGPL-3.0](LICENSE)
