# PLAN Completion Audit

Last updated from local verification on 2026-05-05.

## Objective

Build a self-hosted Android 5 phone extended-display system for macOS with:

- a real macOS virtual display,
- USB transport as the primary path,
- H.264 video streaming to an Android 5 receiver,
- reconnect/reliability behavior for daily monitoring,
- optional Android touch input,
- and a Status Panel fallback that works without virtual-display capture.

## Evidence Checklist

| PLAN requirement | Evidence | Status |
| --- | --- | --- |
| Mac creates a virtual display visible to macOS | Final-acceptance smoke created and released displays ID 56, 57, 59, and 60; see `/tmp/android-monitor-final-acceptance-dry-2/final-acceptance-summary.txt`. | Verified |
| Capture virtual display and encode H.264 | Strict real-capture, normal-window freshness, reconnect, 120-second stability, and cursor smokes captured real frames, encoded Annex-B H.264 with SPS/PPS/IDR, and Android decoded frames. Strict capture tests now also fail if cleanup leaves a stale display. | Verified |
| Android 5-compatible receiver decodes H.264 | AndroidReceiver builds with `minSdk 21`; real phone decode stats recorded in Phase 0/1 docs. | Verified |
| USB transport through ADB reverse | Stream and status paths configure `adb reverse` and were verified on the connected phone. | Verified |
| Custom stream protocol documented | `docs/protocol.md` documents hello/config/stats/error/touch/video/status snapshot messages. `scripts/protocol-smoke.py` now sends stats, touch, and scroll control messages while validating the H.264 packet stream. | Verified |
| Basic settings for resolution/FPS/bitrate | Menu settings and presets are implemented; packaging smoke passes. | Verified |
| Logs and readable errors | Stream, status panel, scripts, and troubleshooting docs record logs and failure paths. | Verified |
| Reconnect without restarting MacHost | `scripts/phase1-reconnect-check.sh` passed; evidence in `docs/phase1-results.md`. | Verified |
| Device detection and one-click menu start | Menu polls `adb devices -l`, disables Start until authorized, and packaged app launch smoke passed. | Build/smoke verified |
| Sleep/wake handling | Menu stops active stream before sleep and attempts restart after wake. | Build verified |
| Lower-latency encoder settings | VideoToolbox realtime mode, no frame reordering, keyframe interval, and data-rate limits are set. | Build verified |
| Adaptive bitrate | Synthetic adaptive smoke lowered 4 Mbps to 3, 2, then 1 Mbps; artifact `/tmp/android-monitor-adaptive-bitrate-smoke.log`. | Verified without capture |
| TCP keepalive | Stream and Status Panel sockets enable keepalive on Mac and Android. | Build verified |
| Cursor visibility | `scripts/cursor-capture-smoke.sh` passed in the 120-second final-acceptance smoke: cursor sweep started, 298 source frames were captured, Android decoded 297 frames, freshness reported `max_adjacent_diff=1.485`, and post-cursor cleanup audit passed. | Verified |
| One-hour stability | `scripts/phase2-stability-check.sh --output-dir /tmp/android-monitor-phase2-stability-onehour` passed on the connected Android 5 phone. It ran 3600.17 seconds, encoded 54000 frames from 13072 captured source frames, ended with Android `decoded=44202 dropped=10 input=15.5 fps`, verified freshness `max_adjacent_diff=144.576`, released display ID 61, and the post-run display audit returned `0`. | Verified |
| Android touch tap/drag | Android sends normalized touch messages; Mac posts CoreGraphics left-mouse events. `scripts/touch-protocol-phone-smoke.sh` passed and verified phone-originated tap/drag control messages over USB against a synthetic stream. `scripts/touch-real-display-phone-smoke.sh` now exists for the post-restart real-display input gate. | Phone protocol verified, real injection pending |
| Android two-finger scroll | Android sends `touch` action `scroll`; Mac posts pixel scroll-wheel events. Localhost protocol smoke exercises the scroll control message, Android unit tests preserve signed deltas, and `scripts/touch-real-display-phone-smoke.sh --require-scroll` can require a manual real-display scroll event. | Build/protocol verified, real scroll pending |
| Accessibility permission request | CLI and menu can check/request Accessibility permission; current launcher is not granted. | Request path verified, grant pending |
| Status Panel fallback | `status-panel-server` and Android Status mode verified over localhost and on phone through `scripts/status-panel-phone-smoke.sh`. Status snapshots include artifact presence and Android unit-test pass/fail counts. | Verified |
| Packaged local Mac app | `scripts/package-mac-host-app.sh` embeds `Android Monitor Host`, `phase0-spike`, and `status-panel-server`; launch smoke passed. | Verified |
| Post-restart gate runner | `scripts/post-restart-runtime-gates.sh --stability-duration 120 --output-root /tmp/android-monitor-final-acceptance-dry-2/runtime-gates` passed Phase 0 real capture, Phase 1 freshness, reconnect, Phase 2 stability, and cleanup audits inside the final-acceptance smoke. | Verified for 120s smoke |
| Final acceptance runner | `scripts/final-acceptance-check.sh --skip-install --stability-duration 120 --output-root /tmp/android-monitor-final-acceptance-dry-2` passed build/package, Status Panel, runtime, cleanup, and cursor gates, then failed at the real touch gate because Accessibility is not granted. | Partial, Accessibility blocked |

## Current Blocker

`scripts/display-audit.sh` currently reports zero stale Android Monitor virtual
displays. The remaining hard blocker is macOS Accessibility permission for the
launcher used by MacHost touch injection. The latest request attempt still
reported permission as not granted.

## Remaining Acceptance Work

1. Grant Accessibility to the launcher used for MacHost.
2. Run `scripts/final-acceptance-check.sh --skip-install` end-to-end after
   Accessibility is granted.
3. Confirm `scripts/display-audit.sh --count` returns `0` after the final run.
4. Record the evidence from
   `/tmp/android-monitor-final-acceptance/final-acceptance-summary.txt` and
   `/tmp/android-monitor-final-acceptance/final-acceptance-manifest.json`.

For a shorter post-restart smoke before the full one-hour run, use:

```sh
scripts/post-restart-runtime-gates.sh --stability-duration 120
```

The goal should not be marked complete until those remaining runtime checks pass
and the results docs are updated with the new evidence.
