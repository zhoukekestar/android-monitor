# Phase 1 Results

Last updated from local verification on 2026-05-05.

## Verified

- `scripts/phase1-window-freshness-check.sh` passes against the connected
  Xiaomi Redmi Note 3 on Android 5.0.2 / API 21.
- The gate launches a normal TextEdit window on the virtual display, streams it
  over USB reverse, and verifies the captured H.264 output locally with
  `ffmpeg` and Pillow.
- Latest evidence:
  - MacHost created display ID 48 at `1024x600`.
  - TextEdit launched at `-974,70 900x420`.
  - ScreenCaptureKit captured 37 source frames over 12 seconds.
  - MacHost submitted 179 H.264 encoder frames at 15 FPS using latest-frame
    repeats when needed.
  - Android reported `decoded=173 dropped=0 input=14.9 fps 1.01 Mbps`.
  - Annex-B verifier reported `SPS=12 PPS=12 IDR=12 NALs=215`.
  - H.264 freshness verifier reported
    `frames=7 max_luma=194.53 max_adjacent_diff=0.248`.
- `scripts/phase1-reconnect-check.sh` passes against the same connected phone.
- Latest reconnect evidence:
  - MacHost created display ID 49 at `1024x600`.
  - TextEdit launched at `-974,70 900x420`.
  - Android connected, decoded initial frames, was force-stopped, then relaunched
    while MacHost continued streaming.
  - MacHost logged a connection reset, a second Android connection, and a second
    `client_hello`.
  - Android reported decoded-frame stats after reconnect, ending at
    `decoded=148 dropped=4 input=14.3 fps 1.75 Mbps`.
  - ScreenCaptureKit captured 62 source frames over 24 seconds.
  - MacHost submitted 360 H.264 encoder frames with 24 keyframes.
  - Annex-B verifier reported `SPS=24 PPS=24 IDR=24 NALs=432`.
- A minimal SwiftPM/AppKit menu-bar shell exists as `android-monitor-host`.
  It starts the proven `phase0-spike` backend as a subprocess.
- The menu shell provides 1024x600 and 1280x720 presets, a persistent Settings
  window for custom width, height, FPS, bitrate, TCP port, and H.264 output
  path, plus Stop, Reveal Log, and Quit menu items.
- The menu shell writes logs to `/tmp/android-monitor-menubar.log`.
- The menu-bar shell builds and passed launch smoke tests: the
  `.build/debug/android-monitor-host` process stayed alive for initialization
  and was then terminated by the test harness, including after the persistent
  settings window was added.
- The menu shell now auto-detects Android device state with periodic
  `adb devices -l` checks. It shows authorized, missing, or unauthorized device
  state in the menu and disables Start until an authorized device is present.
  The device-monitor version also passed a launch smoke test.
- `scripts/package-mac-host-app.sh` packages a local
  `MacHost/build/Android Monitor Host.app` bundle with both the menu executable
  and the `phase0-spike` backend embedded.
- The generated app bundle passed a launch smoke test: both bundled executables
  were present and executable, and
  `MacHost/build/Android Monitor Host.app/Contents/MacOS/Android Monitor Host`
  stayed alive for initialization before the test harness terminated it.
- The current packaged app launch smoke also passed after Status Panel,
  Launch at Login, and Accessibility menu additions. Artifact:
  `/tmp/android-monitor-host-app-launch-smoke.log`.

## Remaining Phase 1 Work

- A full installer is deferred; the current local workflow uses
  `scripts/package-mac-host-app.sh` to produce the app bundle.
