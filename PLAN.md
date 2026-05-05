# Android 5 Phone as macOS Extended Display - Plan

## Goal

Build a self-hosted extended display system for an old Android 5 phone and a Mac.

The target experience is:

- macOS sees a real extra display.
- The mouse can move onto that display.
- Any macOS window can be dragged onto it.
- The Android phone shows that virtual display in real time.
- USB is the primary transport, Wi-Fi can come later.

This is a local/personal tool, not an App Store product.

## Reference Code

Cloned under `references/`:

- `references/SideScreen`
  - Most relevant reference.
  - Shows the full architecture: macOS virtual display, screen capture, VideoToolbox encode, USB ADB reverse, Android MediaCodec decode.
  - Not directly usable because its Android client requires `minSdk = 26` / Android 8 and uses HEVC-first assumptions.
- `references/deskreen`
  - Useful for device discovery, pairing, web-based display ideas, and fallback "status panel" mode.
  - Not enough for true extended display by itself.
- `references/BetterDummy`
  - Useful historical reference for virtual/dummy display behavior on macOS.
  - Good fallback research source if `CGVirtualDisplay` behavior changes.

## Core Decision

Use a two-app architecture:

- `MacHost`: native macOS app that creates and captures the virtual display.
- `AndroidReceiver`: native Android app targeting Android 5 / API 21 that decodes and renders the stream.

Do not start with browser/WebRTC. Android 5 browser compatibility and latency are too uncertain.

## Technical Architecture

### MacHost

Language/runtime:

- Swift + AppKit menu bar app.
- Swift Package first, Xcode project only if packaging needs it.

Responsibilities:

- Create/destroy a virtual display.
- Configure resolution, FPS, bitrate.
- Capture the virtual display.
- Encode frames with VideoToolbox.
- Manage USB transport via `adb reverse`.
- Stream binary video packets to Android.
- Show connection status and logs.

Virtual display:

- Primary practical route: `CGVirtualDisplay`, following the SideScreen reference.
- Important risk: `CGVirtualDisplay` is private API. Fine for local use, risky for distribution.
- Avoid DriverKit Display DEXT for MVP because it requires entitlement/setup complexity.

Capture:

- Prefer ScreenCaptureKit on modern macOS.
- Keep `CGDisplayStream` fallback, because SideScreen already found ScreenCaptureKit can be flaky on virtual displays.

Encoding:

- Use H.264/AVC, not HEVC, for Android 5 compatibility.
- Start with 720p or 1024x600 at 15-30 FPS.
- Use frequent keyframes, e.g. every 1 second.
- Add HEVC later only as an optional modern-device mode.

### AndroidReceiver

Language/runtime:

- Native Android app, `minSdk 21`.
- Prefer Java or conservative Kotlin; keep dependencies low.

Responsibilities:

- Full-screen always-on receiver UI.
- Connect to Mac stream over localhost when `adb reverse` is active.
- Decode H.264 using `MediaCodec`.
- Render to `SurfaceView` or `TextureView`.
- Show lightweight overlay: connection, FPS, bitrate, dropped frames.
- Keep screen awake.

Decoder:

- Use `MediaCodec.createDecoderByType("video/avc")`.
- Render directly to a Surface to avoid CPU copies.
- Handle SPS/PPS and IDR refresh explicitly.

### Transport

MVP transport:

- USB cable + ADB.
- Mac listens on local TCP port, e.g. `38888`.
- Mac runs `adb reverse tcp:38888 tcp:38888`.
- Android connects to `127.0.0.1:38888`.

Why:

- Stable enough for old phones.
- Avoids Wi-Fi latency and router issues.
- Lets the Android app stay simple.

Later:

- Wi-Fi LAN mode.
- QR pairing or manual IP entry.

### Stream Protocol

Use a small custom protocol, not WebRTC for MVP.

Control channel:

- Simple JSON lines or length-prefixed JSON.
- Messages:
  - `client_hello`: Android model, screen size, API level, supported codecs.
  - `stream_config`: width, height, fps, codec, bitrate.
  - `stats`: decoder FPS, queue depth, dropped frames.
  - `error`: readable failure details.

Video channel:

- Binary length-prefixed packets.
- Packet fields:
  - magic/version
  - packet type: config, keyframe, delta frame, cursor, ping
  - sequence number
  - presentation timestamp
  - payload length
  - payload

H.264 format:

- Prefer Annex-B NAL units or a clearly documented length-prefixed format.
- Send SPS/PPS before every IDR until the Android decoder confirms rendering.

## Milestones

### Phase 0 - Feasibility Spikes

Goal: prove the two riskiest pieces before building the full app.

Tasks:

- Build a tiny Mac command-line spike that creates a virtual display.
- Confirm macOS display settings show the virtual display.
- Capture the virtual display for at least 10 seconds.
- Encode a synthetic or captured frame stream as H.264.
- Build a tiny Android 5-compatible decoder test app.
- Verify the actual old phone can decode 720p H.264 smoothly.

Acceptance:

- Mac shows an extra display.
- A test H.264 stream renders on Android 5.
- We know the highest stable resolution/FPS for the device.

### Phase 1 - MVP Extended Display

Goal: drag a macOS window onto the phone and see it.

Tasks:

- Create `MacHost` app skeleton.
- Create `AndroidReceiver` app skeleton.
- Implement USB setup command: find `adb`, run `adb reverse`.
- Implement TCP server and Android TCP client.
- Implement H.264 VideoToolbox encoder.
- Implement Android `MediaCodec` decoder.
- Add basic settings: resolution, FPS, bitrate.
- Add logs and error messages for permissions, ADB, decoder failure.

Initial target settings:

- `1024x600` or `1280x720`.
- `15 FPS` first, then `30 FPS` if stable.
- `2-6 Mbps` bitrate.

Acceptance:

- macOS has a virtual display.
- Terminal or Activity Monitor can be dragged onto it.
- Android phone shows the display with readable text.
- Reconnect works without restarting both apps.

### Phase 2 - Reliability and Usability

Goal: make it pleasant for daily status monitoring.

Tasks:

- Auto-detect connected Android device.
- Auto-start/stop `adb reverse`.
- Keep-alive and reconnect logic.
- FPS/bitrate overlay toggle.
- Proper sleep/wake handling.
- Better resolution presets for old phones.
- Cursor visibility/capture verification.
- Lower-latency encoder settings.
- Adaptive bitrate if decoder falls behind.

Acceptance:

- One-click start from the Mac menu bar.
- One-tap connect on Android.
- Runs for 1 hour without manual recovery.

### Phase 3 - Optional Input

Goal: let the phone also act as a touch surface for the virtual display.

Tasks:

- Android sends touch events with normalized coordinates.
- Mac maps coordinates to virtual display coordinates.
- Mac injects mouse events through CoreGraphics event APIs.
- Request Accessibility permission on Mac.
- Add toggle to disable touch input.

Acceptance:

- Tap, drag, and scroll work on the Android screen.
- Input can be disabled instantly.

### Phase 4 - Status Screen Mode

Goal: add a simpler alternative when full extended display is overkill.

Tasks:

- Build a local dashboard served by MacHost.
- Widgets: terminal command output, logs, CPU/RAM, network, build/test status.
- Android app can switch between "Extended Display" and "Status Panel".

Acceptance:

- User can pin terminal/log/status output without moving windows.
- Status mode works even if virtual display fails.

## Proposed Repo Structure

```text
android-monitor/
  PLAN.md
  references/
    SideScreen/
    deskreen/
    BetterDummy/
  MacHost/
    Package.swift
    Sources/
      MacHost/
      VirtualDisplay/
      Capture/
      Encoding/
      Transport/
  AndroidReceiver/
    settings.gradle
    build.gradle
    app/
      build.gradle
      src/main/
        AndroidManifest.xml
        java/com/androidmonitor/receiver/
  docs/
    protocol.md
    setup.md
    troubleshooting.md
```

## Key Risks

- `CGVirtualDisplay` is private API and may change across macOS versions.
- Android 5 devices vary widely in H.264 decoder quality.
- Old phones may have USB/charging limitations during long sessions.
- Text readability may require careful resolution and bitrate tuning.
- Screen capture permissions can fail silently unless the app guides the user well.

## First Execution Step

When implementation starts, begin with Phase 0:

1. Create a Mac spike based on `references/SideScreen/MacHost/CaptureTest`.
2. Change the encoder path from HEVC to H.264.
3. Create the smallest Android API 21 decoder app.
4. Test with the real Android 5 phone before polishing anything.

