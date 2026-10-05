# godot-ndi 1.2.6 + Stream Rooms audio patch

The Windows DLLs in `bin/windows/` are godot-ndi v1.2.6 (https://github.com/unvermuthet/godot-ndi,
MPL-2.0, (C) 2025-present Henry Muth - unvermuthet and Godot NDI contributors) rebuilt with a small
audio patch. The modified source files and the diff are in `stream_rooms_patch/`. The originals
are backed up in `../../_backup/godot-ndi-1.2.6-original-windows/`.

## Why
The plugin pushed NDI sound into the VideoStreamPlayer once per game frame, capped at what the
NDI frame-sync had queued and truncated to whole samples. A late frame, or a late network packet,
left the player's buffer empty for a moment -> a click. Nothing ever refilled the lost slack.

## What changed
- `VideoStreamNDI.external_audio` (bool) and `VideoStreamNDI.pull_audio(frames, mix_rate)`,
  `get_audio_queue_depth()`: the game pulls the sound itself. Stream Rooms tops up an
  AudioStreamGenerator to a target level every frame, so the frame-sync is pulled exactly as fast
  as the sound card plays (clock-locked), and game hitches only use up slack.
- The built-in path (external_audio = false) is also fixed: fractional samples are carried over,
  no cap at the queue depth, a 60 ms pre-roll, and big pulls are written in chunks instead of
  dropping everything past 4096 samples.

## Rebuilding
Built on Linux with llvm-mingw 20250613 (UCRT) and SCons 4.8.1:
`scons platform=windows use_mingw=yes use_llvm=yes arch=x86_64 target=template_release`
(and `target=template_debug`), from the v1.2.6 tag with `audio-pull.diff` applied.
To go back to the original plugin, copy the two DLLs from the backup folder over these.
