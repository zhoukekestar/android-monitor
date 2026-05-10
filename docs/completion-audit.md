# PLAN Completion Audit

## Current Active Goal Audit - 2026-05-10

Active objective:

1. Device refresh must not hang or get stuck.
2. Multiple connected devices must be selectable and must not accidentally use
   the wrong target.
3. Starting Display mode must report actionable errors instead of a generic
   failure.
4. Compatibility and robustness should improve across Android 5/ADB/macOS
   failure paths, including user-facing recovery instructions.
5. Automated coverage must stay above 95%.

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Refresh devices works and does not backlog/hang | `ADBDeviceMonitor` now coalesces refresh requests and `ADBClient.run` uses bounded timeouts. `scripts/coverage-check.sh` passed on 2026-05-10. | Code/test verified |
| Multiple devices can be selected | Setup window and menu selection both update `selectedDeviceSerial`; `MenuDeviceSelectionTests` cover preserving a selected authorized serial and falling back only when needed. The main shell scripts now share `require_single_authorized_adb_device`, so direct staging/audit/stream checks also fail with explicit `ANDROID_SERIAL=<serial>` guidance when more than one authorized device is connected. | Code/test verified; single-device script path verified |
| Start Display reports useful errors | Menu start runs stale-display audit first and maps display-audit/install/reverse/launch failures through `ADBFailureGuidance`; backend abnormal exits show `/tmp/android-monitor-menubar.log` tail. | Code/test verified |
| Android Studio build/run entry exists | Shared run configs exist for `Android Studio Doctor`, `Prepare Android Studio`, `Build Android Receiver`, `Run Android Receiver`, `Stage Android Receiver APK`, `Launch Installed Android Receiver`, `Uninstall Android Receiver`, `Replace Android Receiver Dry Run`, `Audit Receiver Signature`, `Verify Device Runtime`, `Verify Installed Device Runtime`, `Verify Real Device Runtime`, `Verify Installed Real Device Runtime`, and `Diagnose ADB USB`; `:android-receiver:assembleDebug`, `stageReceiverDebug`, `launchReceiverDebug`, `verifyInstalledDeviceRuntime`, and `replaceReceiverDebugDryRun` passed on 2026-05-10. `scripts/android-studio-doctor.sh` also passed and reported Android Studio JBR, SDK paths, Gradle task visibility, authorized ADB state, receiver signature mismatch, and current stale display state. Doctor is read-only by default and was verified to print that state; `--repair-local-properties` is required to rewrite SDK config and was verified separately. The guarded `replaceReceiverDebug` Gradle task was verified to fail without `-PconfirmUninstall=true`. | Build/stage/launch/runtime verified |
| Packaged Mac app includes required runtime payload | `scripts/package-mac-host-app.sh` passed again on 2026-05-10 after the Android Studio/run-script changes. The bundle contains `Android Monitor Host`, `phase0-spike`, `status-panel-server`, and `android-receiver-debug.apk`; earlier `plutil -lint` and `codesign --verify --deep --strict` checks passed; the bundled `phase0-spike --audit-displays --fail-on-stale-displays` passed. | Package verified |
| Install/run failure gives next action | `checkAdbDevice`, `installReceiverDebug`, `scripts/install-android-receiver.sh`, `scripts/verify-device-runtime.sh`, and `scripts/device-audit.sh` report no-device/unauthorized/offline/multiple-device cases with recovery guidance. `scripts/verify-device-runtime.sh` now also fails early when `ANDROID_SERIAL` names a missing or non-authorized device. It also preflights receiver signatures before install; against the current Redmi device it exits before `adb install -r`, prints both certificate digests, and gives `--skip-install` or `replace-android-receiver.sh --confirm-uninstall` as the next action. The install task treats `adb install` output containing `Failure [...]` as a real Gradle failure, so Android Studio no longer reports success after install failures. `INSTALL_FAILED_USER_RESTRICTED` points to MIUI/USB-install settings and staging; `INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES` now points to launching the installed app or running `Uninstall Android Receiver` before reinstall. `scripts/install-android-receiver.sh` was rerun against the current Redmi device and surfaced that exact guidance while leaving the existing app installed; it now also runs the read-only signature audit automatically for that failure and prints both APK certificate digests. The install script validates local SDK config before Gradle, repairs missing/bad `local.properties` through `scripts/setup-android-env.sh`, and automatically appends ADB/USB diagnostics after a failed install attempt. The phone-runtime scripts resolve `adb` from Android SDK locations before `PATH`, matching Android Studio run-config behavior. The Mac menu treats `offline` as a first-class device state instead of a generic unknown status. | Local no-device, invalid-serial, user-restricted install, and inconsistent-certificate install paths verified; offline code/test verified |
| ADB/USB diagnosis distinguishes “phone connected” from “ADB authorized” | `scripts/adb-usb-diagnose.sh` checks both `adb devices -l` and macOS `ioreg` USB names. It uses the same SDK priority as the build/install/runtime path: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, default `~/Library/Android/sdk`, then `PATH`. When ADB already has an authorized device, USB product-name matching is reported as informational only instead of incorrectly telling the user to change cables or USB mode. | Verified with current authorized Redmi |
| Phone USB stream path works | `scripts/phase0-stream-test.sh --synthetic-only --duration 5 --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --min-decoded-frames 10 --min-input-fps 5` passed on the connected Redmi Note 3. The phone returned `client_hello` for API 21 and final stats included `decoded=69`, `dropped=0`, and `input=15.0 fps`. After the Gradle/JBR and Android Studio run-config fixes, `./gradlew verifyInstalledDeviceRuntime --console=plain` passed using the already installed receiver and the default synthetic stream: final stats included `decoded=145`, `dropped=0`, and `input=14.5 fps`. The default runtime gate now avoids creating macOS virtual displays; real display capture is reserved for `--real-display`/`verifyInstalledRealDeviceRuntime` after stale-display audit is clean. Earlier real Display stream gates passed, but the current WindowServer session now has stale Android Monitor virtual displays and needs logout/restart before strict real-capture testing. | Synthetic phone runtime verified; real capture blocked by current stale displays |
| Coverage above 95% | `scripts/coverage-check.sh` passed on 2026-05-10: Android core was `100/103 = 97.09%`; Swift `MacHostMenuCore` was `214/216 = 99.07%`. The same gate now also runs `scripts/test-adb-device-helper.sh`, which covers no-device, unauthorized, offline, multiple-device, selected-serial, missing-serial, and selected-unauthorized shell paths. It also runs `scripts/test-replace-receiver-helper.sh`, which verifies the replacement helper refuses without confirmation and that `--dry-run` is non-destructive. It also runs `scripts/test-audit-receiver-signature.sh`, which covers matching certificates, warning-only mismatches, and strict mismatch failure. It also runs `scripts/test-android-studio-run-configs.py`, which verifies the shared Android Studio run configurations exist and reference real Gradle tasks. | Verified |

Current blocker:

`adb devices -l` currently sees the Redmi Note 3 as an authorized ADB device.
`scripts/device-audit.sh` confirms Android 5.0.2/API 21 and that
`com.androidmonitor.receiver` is already installed. The current phone-side
install blocker is `INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES`, meaning the
phone already has the same package installed with a different certificate. The
safe paths are to launch the installed app or run `Uninstall Android Receiver`
before reinstalling this build. `scripts/stage-apk.sh` successfully copied the
current APK to `/sdcard/Download/AndroidMonitorReceiver-debug.apk` for manual
install if USB install remains blocked. `scripts/replace-android-receiver.sh`
now provides the command-line replacement path and was verified to refuse
without `--confirm-uninstall`; `scripts/device-audit.sh` confirmed the existing
receiver remained installed after that refusal. The helper also supports
`--dry-run`, and `scripts/test-replace-receiver-helper.sh` covers both
non-destructive paths. `scripts/audit-receiver-signature.sh` pulled the installed
APK read-only and confirmed the current APK certificate SHA-256
`89f3eddcdd298d81e7baa3992e1be9df002315d066cce742e7ca8c8c7c0f5072`
differs from the installed APK certificate SHA-256
`5cf39daee82c8436b14c70b26d95c2f1009046e614df2ebdd5abfb634f694c93`,
which explains the install failure. `./gradlew auditReceiverSignature
--console=plain` also passed and reports the same mismatch as a warning;
`scripts/audit-receiver-signature.sh --fail-on-mismatch` exits `5` as a strict
gate.

`scripts/display-audit.sh` currently reports four stale Android Monitor virtual
displays in this macOS WindowServer session. Start Display and the explicit
`--real-display` gates correctly refuse until logout/restart clears that state.
The default `verifyDeviceRuntime` and `verifyInstalledDeviceRuntime` gates now
use synthetic USB streaming so Android Studio can verify phone launch/decode
without creating more virtual displays.

The remaining install blocker is unchanged: the phone rejects `adb install -r`
for the current APK because the already installed receiver has a different
certificate.

Remaining required evidence before marking this active goal complete:

```sh
scripts/adb-usb-diagnose.sh
scripts/verify-device-runtime.sh
```

The first command must show an authorized ADB device. The second command must
install/launch the Android receiver and pass the short synthetic USB stream test
on the connected phone. On the current Redmi device, run `Uninstall Android
Receiver` only when ready to replace the existing app, then rerun the second
command. The guarded command-line equivalent is
`scripts/replace-android-receiver.sh --confirm-uninstall`; without the flag, it
refuses to uninstall the existing app. Add `--dry-run` to print the replacement
commands without changing the phone. Gradle also exposes
`replaceReceiverDebugDryRun` and a guarded `replaceReceiverDebug` task that
requires `-PconfirmUninstall=true`. `./gradlew replaceReceiverDebugDryRun
--console=plain` passed, and `./gradlew replaceReceiverDebug --console=plain`
refused to uninstall without confirmation; `scripts/device-audit.sh` confirmed
the existing receiver remained installed afterward.

After logout/restart clears stale displays, run the real-display gate:

```sh
scripts/display-audit.sh --fail-on-stale
scripts/verify-device-runtime.sh --skip-install --real-display
```

Last updated from local verification on 2026-05-10.

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
