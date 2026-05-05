# Phase 3 Results

Last updated from local verification on 2026-05-05.

## Verified

- AndroidReceiver has an optional touch-input mode. Touch is off by default.
- Long-pressing the receiver surface toggles touch input on or off; tapping
  still toggles the stats overlay when touch input is off.
- When touch input is enabled, Android sends normalized `touch` JSON control
  messages with `down`, `move`, `up`, and `cancel` actions.
- Android sends two-finger scroll gestures as normalized `touch` messages with
  action `scroll` and `delta_x`/`delta_y` fields.
- MacHost accepts `touch` control messages, maps normalized coordinates onto the
  current virtual display bounds, and posts left-mouse or scroll-wheel
  CoreGraphics events.
- `scripts/touch-protocol-phone-smoke.sh` verifies phone-originated tap and drag
  control messages over USB against a synthetic stream without creating a
  virtual display.
- `scripts/touch-real-display-phone-smoke.sh` is available as the post-restart
  real-display input acceptance helper. It fails fast on stale displays or
  missing Accessibility permission, launches a real TextEdit-backed stream with
  touch enabled, sends ADB tap/drag gestures, and can wait for a manual
  two-finger scroll with `--require-scroll`.
- Android unit tests cover touch coordinate clamping and signed scroll deltas.
- MacHost reports whether Accessibility permission is granted for touch input at
  stream startup.
- Accessibility permission can be checked or requested without creating a
  virtual display through `phase0-spike --check-accessibility-permission`,
  `phase0-spike --request-accessibility-permission`, or the menu app's Request
  Accessibility Permission item.
- Build verification:
  - `swift build`
  - `swift run phase0-spike --check-accessibility-permission`
  - `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :android-receiver:assembleDebug :android-receiver:testDebugUnitTest`
  - `scripts/phase0-check.sh --skip-device`
  - `scripts/touch-protocol-phone-smoke.sh`
  - `bash -n scripts/touch-real-display-phone-smoke.sh`
  - `scripts/touch-real-display-phone-smoke.sh --help`
  - `scripts/package-mac-host-app.sh`

## Remaining Phase 3 Work

- CoreGraphics touch injection and two-finger scroll behavior have not been
  manually verified on a real virtual display because Accessibility permission
  is not granted for the current launcher.
- `scripts/touch-real-display-phone-smoke.sh` now reaches its Accessibility
  preflight in a clean display session and exits before creating another real
  virtual display when permission is missing.
- Accessibility permission request/check paths are implemented, but permission
  is not currently granted for this launcher. It still needs to be granted and
  verified before the manual touch test. Latest request attempt:
  `swift run phase0-spike --request-accessibility-permission` still reported
  `[WARN] Accessibility permission is not granted`.
