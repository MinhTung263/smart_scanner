## 0.0.2

- **Performance & Thermal Optimizations**:
  - Reduced default resolution to 720p (`ResolutionPreset.high`) to decrease CPU/GPU thermal load and memory transfers by >50%.
  - Relaxed software re-focus interval to 3s to prevent camera lens motor overheating.
  - Added Adaptive Frame Throttling (~4 FPS when static, 50 FPS when active).
  - Added Auto-Sleep inactivity timer (60s) with tap-to-resume UI overlay.
- **UI & UX Controls Redesign**:
  - Centered compact single-tap Zoom button (`1x` ➔ `2x` ➔ `3x` ➔ `1x`) with camera viewfinder icon (`Icons.center_focus_strong_rounded`) on the top AppBar.
  - Redesigned Flash button with minimalist bolt icon and gold amber glow when active.

## 0.0.1

- Initial release of `smart_scanner` package.
