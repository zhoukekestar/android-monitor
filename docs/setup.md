# Phase 0 Setup

## Mac Spike

Build:

```sh
cd MacHost
swift build
```

Run the virtual-display capture path:

```sh
swift run phase0-spike --width 1024 --height 600 --fps 15 --bitrate-mbps 4 --duration 10
```

The Mac spike tries ScreenCaptureKit first, then falls back to `CGDisplayStream`
if ScreenCaptureKit is unavailable or fails.

When real capture produces sparse source frames, the spike repeats the latest
captured buffer to keep the encoded stream at the requested FPS. The Mac log
prints both the captured source-frame count and the submitted encoder-frame
count.

Ask macOS for capture permission before testing real display capture:

```sh
swift run phase0-spike --request-screen-capture-permission --duration 1 --no-server
```

Check that permission later without creating a virtual display:

```sh
swift run phase0-spike --check-screen-capture-permission
```

Run only the H.264 encoder and TCP streamer, without creating a virtual display:

```sh
swift run phase0-spike --synthetic-only --duration 60
```

When the TCP server is enabled, the Mac spike tries to run
`adb reverse tcp:38888 tcp:38888` automatically. Use `--no-adb-reverse` if you
want to manage the reverse tunnel yourself.

With streaming enabled, the spike waits up to 8 seconds for Android
`client_hello` before encoding, so the phone receives the first SPS/PPS/IDR
keyframe. Use `--wait-for-client 0` to skip that wait for file-only captures.

The spike writes a raw Annex-B H.264 file to `phase0.h264` unless `--output` is
provided.

Adaptive bitrate is enabled by default. If Android stats show sustained decoder
pressure, MacHost lowers the VideoToolbox target bitrate in-place. Use
`--no-adaptive-bitrate` for fixed-bitrate diagnostics.

The requested virtual-display size is treated as the preferred mode. On macOS
versions where `CGVirtualDisplay` registers a larger backing mode, the spike
prints the actual registered size and uses that size for the encoder and stream
configuration.

## Mac Menu Bar Shell

Build and run the minimal Phase 1 menu-bar shell:

```sh
cd MacHost
swift run android-monitor-host
```

The shell starts the proven `phase0-spike` backend as a subprocess with
1024x600 or 1280x720 presets, plus a Settings window for custom width, height,
FPS, bitrate, TCP port, and H.264 output path. Settings are persisted with
`UserDefaults`. Logs are written to `/tmp/android-monitor-menubar.log`, and the
menu provides device status, Refresh Device, Stop, Reveal Log, and Quit items.
Start is disabled until `adb devices -l` reports an authorized Android device.

To create a local `.app` bundle with the menu shell and `phase0-spike` backend
embedded:

```sh
scripts/package-mac-host-app.sh
```

The bundle is written to `MacHost/build/Android Monitor Host.app`.

The menu app also has Start Status Panel and Stop Status Panel items. Status
Panel mode uses port `38889`, configures `adb reverse tcp:38889 tcp:38889`, and
writes logs to `/tmp/android-monitor-status-panel.log`.

Use the Launch at Login menu item in the packaged app to register or unregister
the host with macOS login items.

Run the status-panel server directly without opening the menu app:

```sh
cd MacHost
swift run status-panel-server
```

This does not create a virtual display, so it remains usable while strict
capture testing is blocked by stale virtual-display state.

## Android Receiver

Initialize local Android SDK paths before building from a fresh checkout or
after moving the repository:

```sh
scripts/setup-android-env.sh
```

Build with any installed Gradle, or reuse the reference Gradle wrapper:

```sh
./gradlew :android-receiver:assembleDebug
```

Install:

```sh
adb install -r -d AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk
```

Connect the Android 5 phone over USB with USB debugging enabled, then reverse the
stream port:

```sh
adb reverse tcp:38888 tcp:38888
```

Start `phase0-spike`, open Android Monitor on the phone, and leave the phone in
landscape. Tapping the screen toggles the status overlay.

Use the bottom-right button in Android Monitor to switch between Extended
Display and Status Panel. Extended Display connects to port `38888` and decodes
the H.264 stream. Status Panel connects to port `38889` and renders Mac host
status snapshots. Long-press the Extended Display surface to toggle optional
touch input on or off.

Collect read-only phone state before or after manual install:

```sh
scripts/device-audit.sh
```

This reports ADB authorization, device identity, display size, AndroidReceiver
package install status, and H.264 decoder hints. It skips `adb reverse --list`
by default because some Android 5 devices disconnect after that diagnostic RPC;
pass `--check-reverse-list` only on devices where that is known to be safe.

Collect read-only Mac display state before strict real-capture testing:

```sh
scripts/display-audit.sh
```

The Mac spike can report the same state without creating a virtual display:

```sh
cd MacHost
swift run phase0-spike --audit-displays
```

## Phase 0 Evidence To Collect

- macOS Displays settings shows `Android Monitor Phase 0`.
- `phase0-spike` reports the virtual display ID as online.
- `phase0-spike` writes non-empty H.264 output and reports encoded frames.
- Android Monitor reports the received resolution, incoming FPS, bitrate,
  decoded frames, and dropped frames.
- Record the highest stable width, height, FPS, and bitrate for the actual
  Android 5 device.

Current local verification notes are tracked in
[`docs/phase0-results.md`](phase0-results.md).

The current end-to-end completion audit is tracked in
[`docs/completion-audit.md`](completion-audit.md).

## Scripted Check

Run build-only checks:

```sh
scripts/phase0-check.sh --skip-device
```

This builds both apps, verifies that the synthetic Annex-B H.264 stream has
SPS/PPS startup config before an IDR frame, and runs a localhost protocol smoke
test against the Mac stream server. It also runs Android local unit tests for
the Annex-B parser and binary packet header parser, then prints a read-only
macOS display audit so stale virtual displays are visible before strict capture
testing.

After USB debugging is authorized on the phone, run the same script without
`--skip-device` to install the APK, configure `adb reverse`, and launch Android
Monitor. The full check also verifies macOS screen-capture permission before
starting the device setup.

If the phone blocks `adb install`, install
`AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk` manually on the
phone. To copy the built APK into the phone's Downloads folder without invoking
`adb install`, run:

```sh
scripts/stage-apk.sh
```

After manual installation, run:

```sh
scripts/phase0-check.sh --skip-install
```

Then run the actual Phase 0 decode/render stream test:

```sh
scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10
```

The stream test configures `adb reverse`, launches Android Monitor, runs the Mac
spike, captures logs under `/tmp/android-monitor-phase0-stream-test`, and fails
unless the Mac receives decoded-frame stats from Android. It force-stops and
relaunches Android Monitor first so repeated runs get a fresh stream client.

To verify real virtual-display capture instead of the synthetic fallback, add a
host-owned animated window and require non-fallback captured frames:

```sh
scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10 --test-content-window --require-real-capture
```

The strict real-capture mode refuses to create another virtual display if old
Android Monitor virtual displays are already online. It also audits after
MacHost exits and fails if the run leaves a stale display behind. Log out or
restart macOS to clear stale `CGVirtualDisplay` instances if either guard
reports any.

The shortcut for that strict gate is:

```sh
scripts/phase0-real-capture-check.sh
```

That shortcut also requires final Android stats of at least 30 decoded frames
and 10 input FPS. For manual tuning, `scripts/phase0-stream-test.sh` accepts
`--min-decoded-frames`, `--min-input-fps`, and `--max-dropped-frames`.

To verify Phase 1 visual freshness with a normal macOS app window, run:

```sh
scripts/phase1-window-freshness-check.sh
```

This launches a marked TextEdit document on the virtual display, streams it to
Android, decodes sampled H.264 frames locally with `ffmpeg`, and verifies the
frames are visible and changing. Artifacts are written under
`/tmp/android-monitor-phase1-window-freshness`.

To verify reconnect without restarting MacHost, run:

```sh
scripts/phase1-reconnect-check.sh
```

This keeps the Mac stream running, force-stops and relaunches AndroidReceiver,
and requires decoded-frame stats after the second `client_hello`.

## Latency Tuning

If cursor movement on the phone feels sluggish, use the menu preset
`1024x600 @ 30 FPS Low Latency`. This keeps resolution conservative for the old
Android 5 decoder while cutting frame cadence from 66 ms to 33 ms. The host also
uses a shallow ScreenCaptureKit queue and the Android overlay is rate-limited so
stats text does not compete with touch handling on the UI thread.

## Optional Touch Input

Android touch input is off by default. Long-press the Android receiver surface
to toggle it on or off. When enabled, Android sends normalized touch events to
MacHost, and MacHost maps them onto the virtual display as left-mouse events.
Use a two-finger gesture on the Android surface to send scroll-wheel input.

On macOS, touch injection may require Accessibility permission for the terminal
or `Android Monitor Host.app` launcher. MacHost prints the current permission
state at stream startup. The menu app has a Request Accessibility Permission
item, and the command-line host can check or request the same permission without
creating a virtual display:

```sh
cd MacHost
swift run phase0-spike --check-accessibility-permission
swift run phase0-spike --request-accessibility-permission
```

To verify the phone-originated tap/drag control path without creating a virtual
display, run:

```sh
scripts/touch-protocol-phone-smoke.sh
```

This uses a synthetic stream and MacHost input-event logging. It does not verify
CoreGraphics injection or two-finger scroll on a real virtual display.

After `scripts/display-audit.sh --count` reports `0` and Accessibility has been
granted to the launcher, run the real-display touch smoke:

```sh
scripts/touch-real-display-phone-smoke.sh --skip-install
```

For the manual two-finger scroll acceptance check, add `--require-scroll` and
perform the gesture on the Android screen while the script is running.

To run the Phase 2 stability gate:

```sh
scripts/phase2-stability-check.sh
```

The default duration is 3600 seconds for the one-hour acceptance run. For a
short smoke run while changing scripts, pass `--duration <seconds>`. The H.264
freshness sampler defaults to `1` FPS; use `--freshness-fps <n>` only for
diagnostics.

To verify cursor capture when the display audit is clean:

```sh
scripts/cursor-capture-smoke.sh
```

This streams a static cursor target, sweeps the macOS cursor over it, and
requires sampled decoded H.264 frames to change.

After logging out or restarting macOS to clear stale virtual displays, run the
capture-dependent gate sequence:

```sh
scripts/post-restart-runtime-gates.sh
```

For a short post-restart smoke before the full one-hour gate:

```sh
scripts/post-restart-runtime-gates.sh --stability-duration 120
```

For the full PLAN acceptance pass after logout/restart and Accessibility grant,
run:

```sh
scripts/final-acceptance-check.sh --skip-install
```

The default final acceptance run includes build/package checks, Status Panel
smokes, the one-hour runtime gate, post-run display cleanup audits, cursor
capture, and real Android tap/drag/two-finger scroll verification. It writes a
summary to `/tmp/android-monitor-final-acceptance/final-acceptance-summary.txt`
and a structured manifest to
`/tmp/android-monitor-final-acceptance/final-acceptance-manifest.json`.

## Status Panel Check

Run the non-capture status-panel smoke:

```sh
scripts/status-panel-smoke.sh
```

The smoke builds `status-panel-server`, starts it without creating a virtual
display, reads one localhost `status_snapshot`, and writes the JSON artifact to
`/tmp/android-monitor-status-panel-smoke/status-snapshot.json`.

Current local verification notes are tracked in
[`docs/phase4-results.md`](phase4-results.md).

With an authorized Android device connected, run the phone Status Panel smoke:

```sh
scripts/status-panel-phone-smoke.sh
```

This installs the debug APK, starts the status-panel server, configures ADB
reverse, switches Android Monitor into Status Panel mode through UI automation,
and requires Android logcat to report a received status snapshot. Artifacts are
written under `/tmp/android-monitor-status-phone-smoke`.
