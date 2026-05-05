# Phase 4 Results

Last updated from local verification on 2026-05-05.

## Verified

- MacHost now includes a `status-panel-server` product that serves JSON status
  snapshots on TCP port `38889`.
- The server configures `adb reverse tcp:38889 tcp:38889` when `adb` is
  available, and it does not create a virtual display.
- Snapshots include host/timestamp, uptime, command output, build artifact
  presence, Android unit-test pass/fail counts, top CPU processes, memory
  statistics, disk capacity, network state, and recent Android Monitor log tail.
- The menu-bar host can start and stop the status panel and reveal
  `/tmp/android-monitor-status-panel.log`.
- `scripts/package-mac-host-app.sh` embeds `status-panel-server` inside
  `MacHost/build/Android Monitor Host.app`.
- AndroidReceiver can switch between Extended Display and Status Panel from the
  bottom-right button. Status mode connects to port `38889`, reconnects on
  failure, and renders the latest snapshot in a scrollable full-screen panel.
- Status Panel mode was verified on the Android phone by installing the debug
  APK, starting `status-panel-server`, tapping the Status button through ADB UI
  automation, and confirming Android logcat snapshot receipt.
- Build and smoke verification:
  - `swift build`
  - `scripts/package-mac-host-app.sh`
  - `test -x "MacHost/build/Android Monitor Host.app/Contents/MacOS/status-panel-server"`
  - `scripts/status-panel-smoke.sh --port 38989`
  - `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :android-receiver:assembleDebug :android-receiver:testDebugUnitTest`
  - `scripts/phase0-check.sh --skip-device`
  - synthetic adaptive-bitrate smoke with artifact
    `/tmp/android-monitor-adaptive-bitrate-smoke.log`
  - `scripts/status-panel-phone-smoke.sh`

## Smoke Evidence

- Status smoke artifact:
  `/tmp/android-monitor-status-panel-smoke/status-snapshot.json`
- Latest smoke result:
  `host=zkk-mac-m1 uptime_seconds=145568 build_status_bytes=174`
- `build_status` reported:
  `Mac debug host: present`, `Mac status server: present`,
  `Mac app bundle: present`, `Android APK: present`, and
  `Android unit tests: pass (10 tests, 0 failures, 0 errors, 0 skipped, 2 suites)`.
- The final build-only Phase 0 regression passed and reported the then-known
  stale Android Monitor virtual display state.
- Phone Status Panel logcat reported snapshots at
  `2026-05-05T07:25:11Z`, `2026-05-05T07:25:13Z`, and
  `2026-05-05T07:25:15Z`.
- Phone smoke artifacts:
  `/tmp/android-monitor-status-phone-smoke/status-panel-server.log`,
  `/tmp/android-monitor-status-phone-smoke/android-status-logcat.log`, and
  `/tmp/android-monitor-status-phone-smoke/window.xml`.
- `scripts/final-acceptance-check.sh` includes both the localhost and phone
  Status Panel smokes before the capture-dependent gates.

## Remaining Phase 4 Work

- No Phase 4-specific work remains. The full final acceptance run is still
  blocked by macOS Accessibility permission for real touch injection.
