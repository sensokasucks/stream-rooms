# godot-spout + Stream Rooms patch

Spout input for Stream Rooms (big screen and presenter podiums). The DLLs in `bin/` are
[godot-spout](https://github.com/buresu/godot-spout) (MIT, (C) buresu) at commit `cab0fca`,
built for Redot 26.2 with a small patch. Spout2 (BSD-2, Lynn Jarvis) and SpoutVulkan are
compiled in; their licences are in `licenses/`.

## What's different from upstream
- **Built against godot-cpp's `4.5` branch** (commit `27d9dd2`) instead of the 4.6 one upstream
  uses: an extension built for Godot 4.6 refuses to load in Redot 26.2 (Godot 4.5).
- **Vulkan backend on** (`-DGODOT_SPOUT_ENABLE_VULKAN=ON`): Redot runs Forward+ on Vulkan here.
- `SpoutTexture.get_sender_names()` (static): the Spout senders running on this PC, for the
  panel's dropdowns.
- The received texture also gets `TEXTURE_USAGE_CAN_COPY_FROM_BIT`, so `get_image()` works
  (tests, snapshots). Note that `get_image()` hands back the BGRA data as if it were RGBA
  (red and blue swapped); drawing the texture shows the right colours.

- **Crash fix (2026-11-06):** upstream threw the whole receiver away whenever one frame's copy
  failed and built a new one the next frame. Each new receiver opens its own Direct3D 11 device,
  and each release waits for the GPU to go idle and sleeps 67 ms, so a sender that is busy for a
  moment (VTube Studio) made that happen up to 60 times a second. On the owner's PC that crashed
  inside NVIDIA's D3D11 driver, corrupted the heap or froze the app, 1 to 2 minutes after a
  podium was put on Spout. Now a failed copy just skips that frame, the receiver is only released
  when the sender is gone, and a new connect is tried at most once a second
  (`SpoutTexture::_receive_texture`, `RETRY_MS`). The PC-wide "active sender" is also only set
  for a receiver's first connect, not every frame (`SpoutVulkanBackend::update_receiver`).

`stream_rooms_patch/stream-rooms.diff` is the change to `src/` and `CMakeLists.txt`; the changed
files are in `stream_rooms_patch/src/` (`SpoutTexture.*` and `SpoutVulkanBackend.*`).

## Rebuilding (Windows, Visual Studio 2022 Build Tools)
```
git clone --recursive https://github.com/buresu/godot-spout.git C:\temp\godot-spout
cd C:\temp\godot-spout && git checkout cab0fca
cd lib\godot-cpp && git fetch origin 4.5 && git checkout 27d9dd2 && cd ..\..
git apply <this folder>\stream_rooms_patch\stream-rooms.diff
git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git C:\temp\Vulkan-Headers
<this folder>\stream_rooms_patch\build_windows.bat
```
`build_windows.bat` needs no Vulkan SDK: it uses the Khronos headers and makes the import
library `vulkan-1.lib` from the `vulkan-1.dll` the graphics driver installs. The DLLs land in
`C:\temp\godot-spout\demo\addons\godot-spout\bin\`; copy them into `bin/` here.
