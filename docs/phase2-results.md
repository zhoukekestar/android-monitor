# Phase 2 Results

Last updated from local verification on 2026-05-05.

## Verified

- The Mac menu shell auto-detects Android device state with periodic
  `adb devices -l` checks and disables Start until an authorized device is
  present.
- The Mac menu shell handles sleep/wake notifications. It stops an active stream
  before sleep and attempts to restart after wake once an authorized device is
  visible again.
- Stream and Status Panel TCP sockets enable TCP keepalive in addition to the
  existing Android reconnect loops and Mac server reconnect handling.
- The menu shell now includes conservative, low-latency, and higher-throughput
  presets: `800x480 @ 15 FPS`, `1024x600 @ 15 FPS`,
  `1024x600 @ 30 FPS Low Latency`, `1280x720 @ 15 FPS`, and
  `1280x720 @ 30 FPS`.
- Low-latency tuning reduced ScreenCaptureKit queue depth from 3 to 2, reduced
  Android decoder input/output wait windows to 2 ms, and rate-limited Android
  overlay stats rendering to 4 Hz so UI text updates do not compete with touch
  handling.
- ScreenCaptureKit capture now explicitly requests cursor visibility in captured
  frames.
- MacHost now enables conservative adaptive bitrate by default. When Android
  stats show sustained decoder pressure, the VideoToolbox target bitrate is
  reduced in-place. Use `--no-adaptive-bitrate` for fixed-bitrate diagnostics.
- Synthetic adaptive-bitrate smoke verified that high-drop Android stats lower
  the encoder target from 4 Mbps to 3 Mbps, then 2 Mbps, then 1 Mbps. Artifact:
  `/tmp/android-monitor-adaptive-bitrate-smoke.log`.
- The menu-bar host has a Launch at Login toggle backed by
  `SMAppService.mainApp`. Build verification passed; actual registration needs
  to be toggled from the packaged app in the logged-in macOS session.
- `scripts/phase2-stability-check.sh` is available for the one-hour stability
  gate. It streams a normal TextEdit window over USB, requires real captured
  frames and Android decoded-frame stats, verifies Annex-B keyframes, and checks
  sampled H.264 frames for visible changing content. The visual sampler now
  defaults to `1` FPS so sparse TextEdit UI changes remain measurable after
  downscaling during long runs.
- `scripts/cursor-capture-smoke.sh` is available for the cursor visibility
  acceptance check. It uses a static cursor target plus a Mac cursor sweep, then
  decodes the H.264 stream locally and fails if sampled frames do not change.
  The final-acceptance smoke verified this path with 298 captured source frames,
  Android `decoded=297 dropped=0`, and H.264 freshness
  `max_adjacent_diff=1.485`.
- `scripts/final-acceptance-check.sh` is available as the full post-restart
  acceptance runner. It includes the one-hour runtime gate, cleanup audits,
  cursor-capture smoke, and real touch/scroll smoke after the non-capture build
  and Status Panel checks. On success it writes both a text summary and
  `final-acceptance-manifest.json` with requirement-to-artifact mappings.
- Virtual-display teardown now keeps the descriptor/settings alive for the
  display lifetime, releases the `CGVirtualDisplay` explicitly, and polls
  briefly before the CLI exits. The final-acceptance smoke released display IDs
  56, 57, 59, and 60 and passed cleanup audits after the runtime and cursor
  gates.
- The direct one-hour stability gate passed on the connected Android 5 phone.
  It completed without manual recovery, released display ID 61, and a post-run
  display audit reported zero stale Android Monitor virtual displays.
- A short low-latency smoke at `1024x600 @ 30 FPS, 3 Mbps` passed with Android
  final stats `decoded=595 dropped=0 input=31.1 fps`, 64 captured source frames
  over 20.16 seconds, and H.264 freshness `max_adjacent_diff=0.281`.

## Latest One-Hour Gate

- Command:
  `scripts/phase2-stability-check.sh --output-dir /tmp/android-monitor-phase2-stability-onehour`
- Result: passed against the connected Android 5 phone.
- Recovery evidence:
  - The Android client reset twice early in the run and reconnected
    automatically without manual intervention.
  - The final Android stats still exceeded the default one-hour minimum of
    32400 decoded frames.
- Stability evidence:
  - MacHost created and released display ID 61.
  - ScreenCaptureKit submitted 54000 encoder frames from 13072 captured source
    frames over 3600.17 seconds.
  - Android final stats:
    `decoded=44202 dropped=10 input=15.5 fps 0.54 Mbps`.
  - Annex-B verification:
    `SPS=3600 PPS=3600 IDR=3600 NALs=64800`.
  - H.264 visual freshness:
    `frames=2160 max_luma=227.25 max_adjacent_diff=144.576`.
  - Post-run cleanup:
    `scripts/display-audit.sh --count` returned `0`.
- Artifacts:
  `/tmp/android-monitor-phase2-stability-onehour/mac-host.log`,
  `/tmp/android-monitor-phase2-stability-onehour/android-logcat.log`,
  `/tmp/android-monitor-phase2-stability-onehour/runner.log`,
  `/tmp/android-monitor-phase2-stability-onehour/stream.h264`, and
  `/tmp/android-monitor-phase2-stability-onehour/decoded-frames/`.

## Latest Final-Acceptance Smoke

- Command:
  `scripts/final-acceptance-check.sh --skip-install --stability-duration 120 --output-root /tmp/android-monitor-final-acceptance-dry-2`
- Result: passed build/package checks, Status Panel smokes, Phase 0/1/2 runtime
  gates, post-runtime cleanup audit, cursor-capture smoke, and post-cursor
  cleanup audit. It then stopped at the expected real-touch Accessibility
  preflight because Accessibility is not granted.
- Stability evidence:
  - MacHost created and released display ID 59.
  - ScreenCaptureKit submitted 1799 encoder frames from 415 captured source
    frames over 120.15 seconds.
  - Android final stats:
    `decoded=1797 dropped=0 input=15.0 fps 1.11 Mbps`.
  - H.264 visual freshness:
    `frames=72 max_luma=195.34 max_adjacent_diff=81.857`.
- Cursor evidence:
  - MacHost created and released display ID 60.
  - Cursor sweep started on the virtual display.
  - ScreenCaptureKit submitted 300 encoder frames from 298 captured source
    frames over 20.16 seconds.
  - Android final stats:
    `decoded=297 dropped=0 input=15.0 fps 0.71 Mbps`.
  - H.264 freshness:
    `frames=12 max_luma=89.50 max_adjacent_diff=1.485`.
- Artifacts:
  `/tmp/android-monitor-final-acceptance-dry-2/final-acceptance-summary.txt`,
  `/tmp/android-monitor-final-acceptance-dry-2/runtime-gates/`, and
  `/tmp/android-monitor-final-acceptance-dry-2/cursor-capture/`.

## Earlier Smoke

- Command:
  `scripts/phase2-stability-check.sh --duration 120 --output-dir /tmp/android-monitor-phase2-stability-rerun`
- Result: passed against the connected Android 5 phone.
- Evidence:
  - MacHost created display ID 55 at `1024x600`.
  - TextEdit launched at `-974,70 900x420`.
  - ScreenCaptureKit submitted 1800 encoder frames from 177 captured source
    frames over 120.15 seconds.
  - Android final stats:
    `decoded=1797 dropped=0 input=15.0 fps 0.59 Mbps`.
  - Annex-B verification:
    `SPS=120 PPS=120 IDR=120 NALs=2160`.
  - H.264 visual freshness:
    `frames=72 max_luma=194.53 max_adjacent_diff=0.283`.
  - Artifacts:
    `/tmp/android-monitor-phase2-stability-rerun/mac-host.log`,
    `/tmp/android-monitor-phase2-stability-rerun/android-logcat.log`,
    `/tmp/android-monitor-phase2-stability-rerun/stream.h264`, and
    `/tmp/android-monitor-phase2-stability-rerun/decoded-frames/`.

## Earlier Smoke Notes

- `/tmp/android-monitor-phase2-stability-smoke` failed correctly because strict
  real capture produced zero frames and fell back to synthetic frames.
- `/tmp/android-monitor-runtime-gates-120/phase2-stability` streamed and decoded
  successfully, but failed the old `0.05` FPS visual freshness sampler because
  sparse TextEdit text changes measured only `max_adjacent_diff=0.036`.

## Remaining Phase 2 Work

- The final acceptance runner still needs to run end-to-end with the default
  one-hour duration after Accessibility is granted.
