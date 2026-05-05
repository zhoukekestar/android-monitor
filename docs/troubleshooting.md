# Troubleshooting

## Android App Never Connects

Check that the phone is visible to ADB:

```sh
adb devices
```

For a fuller read-only device snapshot, run:

```sh
scripts/device-audit.sh
```

If the device shows `unauthorized`, unlock the phone and accept the USB
debugging prompt. If no prompt appears, revoke USB debugging authorizations in
Android Developer Options, unplug/replug USB, then run:

```sh
adb kill-server
adb start-server
adb devices
```

Set up the reverse tunnel again:

```sh
adb reverse --remove tcp:38888
adb reverse tcp:38888 tcp:38888
```

Avoid `adb reverse --list` on Android 5/MIUI devices if it reports a protocol
fault or causes the device to disappear from `adb devices`. The Phase 0 scripts
skip that diagnostic listing by default and rely on the stream connection as the
real verification.

Then restart the Android app.

The Mac spike also runs `adb reverse` automatically when its TCP server is
enabled. Use `--no-adb-reverse` to skip that behavior.

## ADB Install Is Blocked

If `adb install` fails with `INSTALL_FAILED_USER_RESTRICTED`, the phone is
blocking USB installs. On Xiaomi/MIUI devices, enable Developer Options settings
such as:

- `USB debugging`
- `Install via USB`
- `USB debugging (Security settings)`, if present

Unlock the phone, approve any prompts, then rerun:

```sh
scripts/phase0-check.sh
```

If the phone still blocks USB installs, copy or open the debug APK on the phone
and install it manually:

```sh
AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk
```

To stage the built APK in the phone's Downloads folder without running
`adb install`, use:

```sh
scripts/stage-apk.sh
```

Then let the script skip `adb install` and only configure the reverse tunnel and
launch the app:

```sh
scripts/phase0-check.sh --skip-install
```

After the app launches, run the decode/render test:

```sh
scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10
```

If it fails, inspect:

```sh
/tmp/android-monitor-phase0-stream-test/mac-host.log
/tmp/android-monitor-phase0-stream-test/android-logcat.log
```

## Virtual Display Is Created But No Frames Are Captured

The Phase 0 spike tries ScreenCaptureKit first, then `CGDisplayStream`, then
falls back to synthetic frames if real capture cannot start. For the real
capture path, verify:

- Screen Recording permission is granted for the terminal or host app.
- The virtual display is enabled in macOS Displays settings.
- A visible window has been moved onto the virtual display.

For repeatable testing, run:

```sh
scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10 --test-content-window --require-real-capture
```

If the stale-display audit is clean, this shortcut runs the same strict gate:

```sh
scripts/phase0-real-capture-check.sh
```

The shortcut requires final Android stats of at least 30 decoded frames and 10
input FPS. If the stream is visible but this threshold fails, inspect the final
`Android stats` line in the Mac log and rerun `scripts/phase0-stream-test.sh`
with explicit `--min-decoded-frames`, `--min-input-fps`, or
`--max-dropped-frames` values while tuning.

Strict real-capture mode also audits display cleanup after MacHost exits. If
the run streamed and decoded successfully but then fails with stale displays,
the video path is working but virtual-display teardown still needs a clean
session fix before the acceptance gate can pass.

If the Mac log says `ScreenCaptureKit submitted ... encoder frames from ...
captured source frame(s)`, the capture backend was sparse and the stream used
latest-frame repeats to maintain FPS. That is acceptable for the Phase 0 gate,
but visual freshness should still be checked with a normal window on the
virtual display.

Run the normal-window freshness gate:

```sh
scripts/phase1-window-freshness-check.sh
```

If this fails in the `verify-h264-freshness.py` step, inspect the decoded PNGs
under `/tmp/android-monitor-phase1-window-freshness/decoded-frames` to see
whether the H.264 stream is black, static, or just changing below the current
threshold.

## Reconnect Gate Fails

Run:

```sh
scripts/phase1-reconnect-check.sh
```

The Mac log should contain at least two `Android hello` lines and decoded-frame
stats after the second one. If the second hello appears but decoded stats do not,
the Android decoder likely reconnected mid-GOP and did not receive a usable
SPS/PPS/IDR refresh quickly enough. If the second hello never appears, inspect
ADB reverse setup and Android logs in `/tmp/android-monitor-phase1-reconnect`.

## Status Panel Does Not Connect

Start the Mac status-panel server from the menu app or directly:

```sh
cd MacHost
swift run status-panel-server
```

Then switch Android Monitor to Status Panel with the bottom-right button. The
server configures `adb reverse tcp:38889 tcp:38889` automatically when `adb` is
available. If the phone still shows a retry message, run:

```sh
adb reverse --remove tcp:38889
adb reverse tcp:38889 tcp:38889
scripts/status-panel-smoke.sh
```

Inspect `/tmp/android-monitor-status-panel.log` for menu-launched runs, or
`/tmp/android-monitor-status-panel-smoke/status-snapshot.json` for the localhost
smoke artifact. Status Panel mode does not create or capture a virtual display,
so stale `CGVirtualDisplay` state should not block it.

## Stability Gate Fails

Run:

```sh
scripts/phase2-stability-check.sh
```

For quick diagnostics, use `--duration 120`. The default is the one-hour
acceptance run. If the check fails, inspect
`/tmp/android-monitor-phase2-stability/mac-host.log` for capture gaps and final
Android stats, then inspect decoded PNGs under
`/tmp/android-monitor-phase2-stability/decoded-frames` to separate transport
failure from black/static capture.

If this fails with `MacHost fell back to synthetic frames`, inspect the Mac log.
If it also reports stale or unavailable virtual display identity, log out or
restart macOS to clear old `CGVirtualDisplay` instances, then rerun the strict
test.

If the strict test fails before launching with a stale-display count, the guard
is preventing another leaked display from being created in an already dirty
WindowServer session. Restart/logout is the right next step; use
`--allow-stale-virtual-displays` only for diagnostics.

If it fails after streaming with a stale-display count, treat that as a teardown
failure, not a decoder failure. The current WindowServer state still needs
logout/restart before strict capture testing can be retried.

To inspect that state directly:

```sh
scripts/display-audit.sh
```

Or from the Mac host binary:

```sh
cd MacHost
swift run phase0-spike --audit-displays --fail-on-stale-displays
```

On modern macOS, open System Settings, go to Privacy & Security, then Screen &
System Audio Recording, and enable the terminal or app that launches
`phase0-spike`. Quit and reopen that terminal after changing the permission.

The spike can also trigger the macOS permission prompt:

```sh
swift run phase0-spike --request-screen-capture-permission --duration 1 --no-server
```

After changing the setting and reopening the terminal, verify it without creating
a virtual display:

```sh
swift run phase0-spike --check-screen-capture-permission
```

## Android Decoder Errors

Start with conservative settings:

```sh
swift run phase0-spike --width 1024 --height 600 --fps 15 --bitrate-mbps 2
```

If that fails, try `800x480` at `15 FPS`. Android 5 devices vary a lot in H.264
decoder limits, especially over long sessions while charging.
