# Phase 0 Results

Last updated from local verification on 2026-05-05.

## Verified

- `MacHost` builds with Swift Package Manager.
- `AndroidReceiver` builds with the repo-owned Gradle wrapper.
- `scripts/phase0-check.sh --skip-install` passes against the connected phone.
- `scripts/phase0-check.sh --skip-device` passes and now prints the read-only
  macOS display audit before finishing.
- Synthetic H.264 encode works and writes non-empty Annex-B output.
- The scripted build-only check verifies Annex-B SPS/PPS/IDR startup config and
  the localhost stream protocol header/config path, including configured bitrate.
- Android local unit tests cover the receiver Annex-B parser and binary packet
  header parser.
- `scripts/phase0-stream-test.sh` is available for the post-install
  decode/render run and requires Android decoded-frame stats before passing.
- The Phase 0 protocol now includes Android `client_hello`, periodic decoder
  `stats`, and readable `error` control messages back to the Mac host.
- The Android receiver now gates decoder startup until it receives one
  Annex-B packet containing SPS, PPS, and an IDR frame.
- The Android receiver waits briefly for hardware decoder output after queued
  frames and sends decoded-frame stats as soon as frames are released, which
  keeps sparse real captures observable by the Mac test harness.
- MacHost waits for Android `client_hello` before encoding when streaming is
  enabled, so the first delivered video packet is a config-bearing IDR instead
  of being dropped before the receiver is ready.
- macOS screen-capture permission is now granted for the launcher environment.
- `CGVirtualDisplay` creation works. The host now advertises only the requested
  mode instead of forcing a `1920x1200` descriptor, so conservative settings
  such as `1024x600` register at the requested size.
- MacHost now has `--test-content-window` to place animated host-owned content
  on the current virtual display, and `scripts/phase0-stream-test.sh` has
  `--require-real-capture` to reject synthetic fallback and post-run stale
  virtual displays when real capture is being verified.
- Strict real-capture testing now preflights for stale Android Monitor virtual
  displays and refuses to create another one unless
  `--allow-stale-virtual-displays` is passed for diagnostics. It also audits
  after MacHost exits so a streamed/decode-successful run cannot hide a leaked
  virtual display.
- `scripts/display-audit.sh` reports macOS display state and counts stale
  Android Monitor virtual displays without creating any new displays.
- `phase0-spike --audit-displays` reports the same read-only display state from
  the Mac host binary; `--fail-on-stale-displays` exits `11` when stale displays
  are present.
- `phase0-spike --cursor-test-window` can show a static cursor target and sweep
  the macOS cursor across the virtual display for cursor-capture verification.
- `scripts/phase0-real-capture-check.sh` is the post-restart shortcut for the
  strict real-capture gate.
- `scripts/phase0-stream-test.sh` now supports quality thresholds:
  `--min-decoded-frames`, `--min-input-fps`, and `--max-dropped-frames`. The
  post-restart gate requires at least 30 decoded frames and 10 input FPS.
- `scripts/phase0-stream-test.sh` force-stops `AndroidReceiver` before launch
  so repeated test runs start a fresh stream client instead of just foregrounding
  an old Activity task.
- `--test-content-window` now converts CoreGraphics display bounds into AppKit
  window coordinates when `NSScreen` has not published the new virtual display,
  fills the virtual-display work area, and logs the final test window frame.
- The real-capture path now submits encoder frames at the requested cadence by
  repeating the latest captured source buffer when ScreenCaptureKit is sparse.
  Logs distinguish actual source frames from repeated encoder frames.
- The connected phone is authorized over ADB and reports:
  - Manufacturer: Xiaomi
  - Model: Redmi Note 3
  - Android: 5.0.2 / API 21
  - Display: 1080x1920 at about 59.95 Hz, density 480
  - Hardware AVC decoder advertised: `OMX.MTK.VIDEO.DECODER.AVC`
- `AndroidReceiver` is installed on the phone. The latest observed path is
  `/data/app/com.androidmonitor.receiver-2/base.apk`.
- USB `adb reverse tcp:38888 tcp:38888` setup is accepted by the phone.
- The actual Android 5 synthetic decode/render stream test passes:
  - Command:
    `scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10`
  - Evidence:
    Android connected, received the stream over USB reverse, and reported
    decoded-frame stats. With an empty virtual display, both real capture
    backends returned zero frames and the test used the synthetic fallback.
    Latest fallback result: `decoded=41 dropped=0 input=15.0 fps`.
  - Artifacts:
    `/tmp/android-monitor-phase0-stream-test-1024x600-cgdisplay-fallback/mac-host.log`,
    `/tmp/android-monitor-phase0-stream-test-1024x600-cgdisplay-fallback/android-logcat.log`,
    and
    `/tmp/android-monitor-phase0-stream-test-1024x600-cgdisplay-fallback/stream.h264`.
- The strict real-capture gate now passes after a clean display audit:
  - Command:
    `scripts/phase0-real-capture-check.sh`
  - Evidence:
    MacHost created display ID 46 at `1024x600`, placed the animated test window
    at `-984,557 944x520`, waited for Android `client_hello`, captured 16
    ScreenCaptureKit source frames, and submitted 150 H.264 encoder frames at
    the requested 15 FPS using latest-frame repeats.
  - Android stats:
    `decoded=148 dropped=0 input=15.0 fps 1.59 Mbps`.
  - H.264 verification:
    `SPS=10 PPS=10 IDR=10 NALs=180`.
  - Artifacts:
    `/tmp/android-monitor-phase0-stream-test/mac-host.log`,
    `/tmp/android-monitor-phase0-stream-test/android-logcat.log`, and
    `/tmp/android-monitor-phase0-stream-test/stream.h264`.
- The Phase 1 normal-window freshness gate passes:
  - Command:
    `scripts/phase1-window-freshness-check.sh`
  - Evidence:
    MacHost created display ID 48 at `1024x600`, launched a normal TextEdit
    window at `-974,70 900x420`, waited for Android `client_hello`, captured 37
    ScreenCaptureKit source frames, and submitted 179 H.264 encoder frames.
  - Android stats:
    `decoded=173 dropped=0 input=14.9 fps 1.01 Mbps`.
  - H.264 verification:
    `SPS=12 PPS=12 IDR=12 NALs=215`.
  - Local visual freshness verification:
    `frames=7 max_luma=194.53 max_adjacent_diff=0.248`, so sampled decoded
    frames were visible and changing.
  - Artifacts:
    `/tmp/android-monitor-phase1-window-freshness/mac-host.log`,
    `/tmp/android-monitor-phase1-window-freshness/android-logcat.log`,
    `/tmp/android-monitor-phase1-window-freshness/stream.h264`, and
    `/tmp/android-monitor-phase1-window-freshness/decoded-frames/`.
- Synthetic decoder throughput on the actual phone has been verified with the
  optimized synthetic frame generator:
  - `1280x720 @ 15 FPS, 3 Mbps`: latest stats
    `decoded=130 dropped=11 input=15.0 fps`.
  - `1280x720 @ 30 FPS, 4 Mbps`: latest stats
    `decoded=266 dropped=17 input=30.0 fps`.
  - `1920x1080 @ 30 FPS, 6 Mbps`: latest stats
    `decoded=264 dropped=22 input=29.9 fps`.
  - `1920x1200 @ 30 FPS, 6 Mbps`: latest stats
    `decoded=234 dropped=29 input=28.9 fps`.

## Current Limitations

- This Android 5/MIUI `adbd` accepts reverse setup but `adb reverse --list`
  fails with `protocol fault (couldn't read status length)` and can disconnect
  the device. Phase 0 scripts now skip that diagnostic call by default.
- ScreenCaptureKit source-frame delivery on the virtual display can be sparse.
  The host-owned animated window produced 16 captured source frames over 10
  seconds, while the normal TextEdit window produced 37 source frames over 12
  seconds. The stream remains stable by repeating the latest real captured
  buffer.
- Empty virtual-display capture can still return zero frames from both
  ScreenCaptureKit and `CGDisplayStream`; the spike falls back to synthetic
  frames for encoder/decoder validation unless `--require-real-capture` is set.
- Earlier same-session capture diagnostics before the display lifecycle fixes:
  - The legacy `CGDisplayCreateImage` symbol returned a `1024x600` image for
    display 39, but all sampled pixels were black.
  - `screencapture -D 2` produced a `1920x1200` PNG for a stale virtual display,
    but all sampled pixels were black.
  - `AVCaptureScreenInput(displayID: 39)` could add input/output but timed out
    after 10 seconds with 0 frames.
  - The upstream SideScreen `CaptureTest` reference could not create its fixed
    `1920x1200` display while a stale display identity already existed.
- Latest threshold smoke evidence:
  `scripts/phase0-stream-test.sh --synthetic-only --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10 --min-decoded-frames 30 --min-input-fps 10 --output-dir /tmp/android-monitor-phase0-threshold-smoke`
  passed on the real Android phone with final stats
  `decoded=127 dropped=9 input=15.1 fps`.
- After the strict cleanup-audit and cursor-test additions,
  `scripts/phase0-check.sh --skip-device` passed without creating another
  virtual display.
- `scripts/package-mac-host-app.sh` passed after the cursor-test additions and
  rebuilt `MacHost/build/Android Monitor Host.app`.
- `scripts/final-acceptance-check.sh --skip-install --stability-duration 120`
  passed the initial audit, build/package checks, Status Panel smokes,
  120-second runtime gates, cleanup audits, and cursor-capture smoke before
  stopping at the expected Accessibility preflight for real touch injection.
- The current display audit reports zero stale Android Monitor virtual displays.
  The stale-display guard remains in place to avoid creating additional strict
  test displays if WindowServer state becomes dirty again.
- The highest stable setting actually tested on the phone is `1920x1200 @ 30
  FPS, 6 Mbps` with simple synthetic content. For Phase 1 MVP work, start more
  conservatively at `1280x720 @ 30 FPS` or `1024x600 @ 15-30 FPS`, then retest
  with real moving desktop content.

## Next Action

Phase 0 now proves virtual-display creation, real ScreenCaptureKit source-frame
capture, H.264 encode, USB transport, and Android 5 hardware decode/render at a
stable 1024x600 @ 15 FPS stream cadence. The Phase 1 freshness gate also proves
that a normal macOS app window can be placed on the virtual display and appears
in decoded H.264 frames.

Current acceptance blocker: grant macOS Accessibility permission for the
launcher used by MacHost touch injection, then run the final acceptance runner
end-to-end and record its summary/manifest artifacts.
