# Troubleshooting

## Android Studio Build Or Run Does Nothing

Open the repository root in Android Studio:

```text
/Users/zkk/workspace/android-monitor
```

Before opening Android Studio, or after moving the repo, initialize local SDK
paths:

```sh
scripts/setup-android-env.sh
```

The project includes shared run configurations:

- `Android Studio Doctor`: runs read-only environment, Gradle, ADB, signature, and display diagnostics.
- `Prepare Android Studio`: rewrites local SDK config for both Gradle entry points.
- `Build Android Receiver`: builds the APK with `:android-receiver:assembleDebug`.
- `Run Android Receiver`: builds, installs, and launches the phone app through ADB.
- `Stage Android Receiver APK`: copies the built APK to the phone Downloads folder for manual install.
- `Launch Installed Android Receiver`: launches the already installed phone app without running `adb install`.
- `Uninstall Android Receiver`: removes the installed phone app before reinstalling a differently signed build.
- `Replace Android Receiver Dry Run`: shows the uninstall/reinstall verification commands without changing the phone.
- `Audit Receiver Signature`: compares the current APK signature with the installed phone app.
- `Verify Device Runtime`: installs if possible, launches the phone app, and runs a synthetic USB stream/decode gate without creating a macOS virtual display.
- `Verify Installed Device Runtime`: runs the same synthetic stream/decode gate using the already installed phone app.
- `Verify Real Device Runtime`: runs the stricter real virtual-display capture gate after stale-display audit is clean.
- `Verify Installed Real Device Runtime`: runs the same real virtual-display gate using the already installed phone app.
- `Diagnose ADB USB`: prints ADB and macOS USB diagnostics when the phone is not installable.

If you open `AndroidReceiver/` directly, the local SDK file
`AndroidReceiver/local.properties` points that subproject at the same Android
SDK path used by the root project. Because `local.properties` is intentionally
not committed, rerun `scripts/setup-android-env.sh` if this file is missing.

If command-line Gradle exits before doing any work, check `JAVA_HOME`. This
machine previously had `JAVA_HOME=/opt/homebrew/opt/openjdk@11`, but that path
does not exist. The project scripts now fall back to Android Studio's bundled
JBR automatically; direct `./gradlew ...` calls should use:

```sh
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :android-receiver:assembleDebug
```

For install/run diagnostics, prefer:

```sh
scripts/install-android-receiver.sh
scripts/verify-device-runtime.sh
scripts/adb-usb-diagnose.sh
```

These scripts resolve `adb` from `ANDROID_HOME`, `ANDROID_SDK_ROOT`, the default
Android Studio SDK path, and then `PATH`. This avoids Android Studio run
configurations failing silently when their shell PATH does not include
`platform-tools`.

`scripts/android-studio-doctor.sh` is read-only by default. To let it repair
`local.properties` as part of the run:

```sh
scripts/android-studio-doctor.sh --repair-local-properties
```

## Android App Never Connects

Check that the phone is visible to ADB:

```sh
adb devices
```

If `adb devices` only prints the header, run:

```sh
scripts/adb-usb-diagnose.sh
```

If the diagnostic shows only hubs/keyboards and no Android-like USB device,
macOS is not seeing the phone at all. Use a data-capable cable, avoid unpowered
hubs, unlock the phone, and change the phone USB mode from charge-only to file
transfer, MIDI, or PTP.

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

If the device shows `offline`, keep the phone unlocked, unplug/replug USB, and
restart the ADB server with the same commands above. The Mac setup window also
reports `offline` explicitly and asks you to refresh devices after recovery.

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

## Mac Menu Does Not Refresh Or Select The Right Device

Use the setup window's `刷新设备` button after plugging or unplugging phones. A
successful refresh clears the temporary `正在刷新设备...` message and returns to
the current device state.

Device refresh uses a bounded ADB command timeout. If ADB hangs, the app reports
an ADB timeout instead of leaving the setup window stuck in refresh state. The
recovery path is to unplug/replug USB, unlock the phone, approve USB debugging,
and if needed run:

```sh
adb kill-server
adb start-server
```

When more than one authorized phone is connected, select the target phone from
the setup window's `投屏设备` dropdown before starting Display or Status mode.
The menu-bar `Choose Device` submenu uses the same selected serial. If command
line install or verification scripts are used with multiple devices, set:

```sh
ANDROID_SERIAL=<adb-serial> scripts/install-android-receiver.sh
```

The direct Gradle install task and the main phone scripts intentionally fail
fast when no authorized device is present or when multiple devices are connected
without `ANDROID_SERIAL`.

## Start Display Fails Before Streaming

Start Display runs a stale-display audit before creating a new virtual display.
If it reports a stale Android Monitor display, log out or restart macOS before
retrying. Stale virtual displays can make macOS capture an old or invalid
display.

If the stream backend exits immediately, the menu app shows the latest
`/tmp/android-monitor-menubar.log` lines. Check the message in this order:

- Screen Recording permission is granted for Android Monitor Host/phase0-spike.
- No stale Android Monitor virtual displays remain.
- The selected phone is still authorized in `adb devices`.
- The phone app is installed and launchable.

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

In Android Studio, use `Stage Android Receiver APK` for the same copy step.
After installing from the phone's Downloads app, use `Launch Installed Android
Receiver` to start the app without retrying `adb install`.

If `adb install` fails with
`INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES`, the phone already has the same
package installed with a different signing certificate. Use `Launch Installed
Android Receiver` if the existing app is good enough. To install the current
build, run `Uninstall Android Receiver` first, then rerun `Run Android
Receiver`. Do not uninstall the working app until USB install is allowed or the
staged APK can be installed manually.

To confirm the signature mismatch without changing the phone:

```sh
scripts/audit-receiver-signature.sh
```

For the same replacement path from the command line, use the guarded helper:

```sh
scripts/replace-android-receiver.sh --confirm-uninstall
```

The helper refuses to run without `--confirm-uninstall`. To inspect the exact
commands without uninstalling anything:

```sh
scripts/replace-android-receiver.sh --confirm-uninstall --dry-run
```

The Gradle equivalent is:

```sh
./gradlew replaceReceiverDebugDryRun --console=plain
./gradlew replaceReceiverDebug -PconfirmUninstall=true --console=plain
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

For the full final phone-connected gate, run:

```sh
scripts/verify-device-runtime.sh
```

This gate preflights receiver signatures before installing. If the installed
phone app is signed differently, it stops before `adb install -r` and prints the
same keep-or-replace options.

By default, this gate streams synthetic H.264 frames through USB so Android
Studio can verify phone launch/decode without creating another macOS virtual
display. For real extended-display capture, first clear stale displays, then run
the explicit real-display variant:

```sh
scripts/display-audit.sh --fail-on-stale
scripts/verify-device-runtime.sh --real-display
```

If the receiver is already installed and reinstall is blocked by phone policy or
certificate mismatch, verify the runtime without replacing the app:

```sh
scripts/verify-device-runtime.sh --skip-install
```

When multiple authorized phones are connected, choose the target serial:

```sh
ANDROID_SERIAL=<adb-serial> scripts/verify-device-runtime.sh
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
