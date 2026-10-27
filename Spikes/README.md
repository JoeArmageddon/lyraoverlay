# Spikes

Early experiments kept for reference (`overlay-spike`, `overlay-variants`, `audio-spike`).

- **Audio:** ScreenCaptureKit audio-only capture worked (48 kHz planar stereo). Superseded by a Core Audio tap
  in LyraCore.
- **Lock-screen overlay: failed on macOS 27.** Private SkyLight spaces (max level, system space type, window
  tags, sublevels, re-applying on lock) left the window listed and "on screen" while locked but never visible.
  Logs: `overlay-spike.log`, `overlay-variants.log`. Lyra therefore only draws on the unlocked desktop.
  A viable lock-screen approach (for example a screen saver bundle) would be a welcome contribution.
