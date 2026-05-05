import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import IOSurface
@preconcurrency import ScreenCaptureKit

struct CaptureResult {
    let frameCount: Int
    let elapsedSeconds: TimeInterval
}

private final class CadencedFrameEncoder: @unchecked Sendable {
    private let encoder: H264Encoder
    private let fps: Int
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var sourceFrameCount = 0

    init(encoder: H264Encoder, fps: Int) {
        self.encoder = encoder
        self.fps = fps
    }

    func update(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latestPixelBuffer = pixelBuffer
        sourceFrameCount += 1
        lock.unlock()
    }

    func currentSourceFrameCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sourceFrameCount
    }

    func encodeForDuration(_ durationSeconds: TimeInterval) -> Int {
        let frameTotal = max(1, Int(durationSeconds * Double(fps)))
        let frameDuration = 1.0 / Double(fps)
        let start = CFAbsoluteTimeGetCurrent()
        var submittedFrames = 0

        for tick in 0..<frameTotal {
            if let pixelBuffer = latestFrame() {
                let pts = CMTime(value: CMTimeValue(submittedFrames), timescale: CMTimeScale(fps))
                encoder.encode(
                    pixelBuffer: pixelBuffer,
                    presentationTimeStamp: pts,
                    forceKeyframe: submittedFrames == 0 || submittedFrames % fps == 0
                )
                submittedFrames += 1
            }

            let targetElapsed = Double(tick + 1) * frameDuration
            let actualElapsed = CFAbsoluteTimeGetCurrent() - start
            if actualElapsed < targetElapsed {
                waitForNextCadenceTick(targetElapsed - actualElapsed)
            }
        }

        return submittedFrames
    }

    private func latestFrame() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latestPixelBuffer
    }

    private func waitForNextCadenceTick(_ seconds: TimeInterval) {
        if Thread.isMainThread {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: seconds))
        } else {
            Thread.sleep(forTimeInterval: seconds)
        }
    }
}

private final class CaptureResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<CaptureResult, Error>?

    func set(_ result: Result<CaptureResult, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<CaptureResult, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

func captureDisplay(
    displayID: CGDirectDisplayID,
    width: Int,
    height: Int,
    fps: Int,
    durationSeconds: TimeInterval,
    encoder: H264Encoder
) throws -> CaptureResult {
    do {
        print("[INFO] Trying ScreenCaptureKit capture")
        let result = try captureDisplayWithScreenCaptureKit(
            displayID: displayID,
            width: width,
            height: height,
            fps: fps,
            durationSeconds: durationSeconds,
            encoder: encoder
        )
        if result.frameCount > 0 {
            return result
        }
        print("[WARN] ScreenCaptureKit completed without frames")
        print("[INFO] Trying CGDisplayStream fallback")
    } catch {
        print("[WARN] ScreenCaptureKit capture failed: \(error)")
        print("[INFO] Trying CGDisplayStream fallback")
    }

    return try captureDisplayWithCGDisplayStream(
        displayID: displayID,
        width: width,
        height: height,
        fps: fps,
        durationSeconds: durationSeconds,
        encoder: encoder
    )
}

private func captureDisplayWithCGDisplayStream(
    displayID: CGDirectDisplayID,
    width: Int,
    height: Int,
    fps: Int,
    durationSeconds: TimeInterval,
    encoder: H264Encoder
) throws -> CaptureResult {
    let queue = DispatchQueue(label: "android-monitor.phase0.capture")
    let start = CFAbsoluteTimeGetCurrent()
    let pixelFormat = Int32(kCVPixelFormatType_32BGRA)
    let captureWidth = Int(CGDisplayPixelsWide(displayID))
    let captureHeight = Int(CGDisplayPixelsHigh(displayID))
    let cadence = CadencedFrameEncoder(encoder: encoder, fps: fps)

    if captureWidth != width || captureHeight != height {
        print("[INFO] Registered display size is \(captureWidth)x\(captureHeight); requested \(width)x\(height)")
    }

    guard let stream = CGDisplayStream(
        dispatchQueueDisplay: displayID,
        outputWidth: captureWidth,
        outputHeight: captureHeight,
        pixelFormat: pixelFormat,
        properties: nil,
        queue: queue,
        handler: { status, _, surface, _ in
            guard status == .frameComplete, let surface else {
                return
            }

            var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
            let createStatus = CVPixelBufferCreateWithIOSurface(
                kCFAllocatorDefault,
                surface,
                nil,
                &unmanagedPixelBuffer
            )
            guard createStatus == kCVReturnSuccess,
                  let pixelBuffer = unmanagedPixelBuffer?.takeRetainedValue() else {
                print("[WARN] CVPixelBufferCreateWithIOSurface failed: \(createStatus)")
                return
            }

            cadence.update(pixelBuffer: pixelBuffer)
        }
    ) else {
        throw SpikeError.capture("CGDisplayStream returned nil")
    }

    let startResult = stream.start()
    guard startResult == .success else {
        throw SpikeError.capture("CGDisplayStream.start failed with \(startResult)")
    }

    let submittedFrames = cadence.encodeForDuration(durationSeconds)
    stream.stop()

    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let sourceFrameCount = cadence.currentSourceFrameCount()
    if sourceFrameCount > 0 && submittedFrames > sourceFrameCount {
        print("[INFO] CGDisplayStream submitted \(submittedFrames) encoder frames from \(sourceFrameCount) captured source frame(s)")
    }
    return CaptureResult(frameCount: sourceFrameCount, elapsedSeconds: elapsed)
}

private final class ScreenCaptureFrameHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let cadence: CadencedFrameEncoder

    init(cadence: CadencedFrameEncoder) {
        self.cadence = cadence
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        cadence.update(pixelBuffer: pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[WARN] ScreenCaptureKit stream stopped: \(error.localizedDescription)")
    }
}

private func captureDisplayWithScreenCaptureKit(
    displayID: CGDirectDisplayID,
    width: Int,
    height: Int,
    fps: Int,
    durationSeconds: TimeInterval,
    encoder: H264Encoder
) throws -> CaptureResult {
    guard #available(macOS 14.0, *) else {
        throw SpikeError.capture("ScreenCaptureKit requires macOS 14+")
    }

    let resultBox = CaptureResultBox()
    let done = DispatchSemaphore(value: 0)
    let runner = DispatchQueue(label: "android-monitor.phase0.scstream.runner")

    runner.async {
        Task {
            resultBox.set(
                await captureDisplayWithScreenCaptureKitAsync(
                    displayID: displayID,
                    width: width,
                    height: height,
                    fps: fps,
                    durationSeconds: durationSeconds,
                    encoder: encoder
                )
            )
            done.signal()
        }
    }

    let waitSucceeded = waitForSemaphore(done, timeoutSeconds: durationSeconds + 8)
    if !waitSucceeded {
        throw SpikeError.capture("ScreenCaptureKit timed out")
    }

    switch resultBox.get() {
    case .success(let captureResult):
        return captureResult
    case .failure(let error):
        throw error
    case .none:
        throw SpikeError.capture("ScreenCaptureKit returned no result")
    }
}

@available(macOS 14.0, *)
private func captureDisplayWithScreenCaptureKitAsync(
    displayID: CGDirectDisplayID,
    width: Int,
    height: Int,
    fps: Int,
    durationSeconds: TimeInterval,
    encoder: H264Encoder
) async -> Result<CaptureResult, Error> {
    let start = CFAbsoluteTimeGetCurrent()

    do {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            let availableIDs = content.displays.map { $0.displayID }
            throw SpikeError.capture("display \(displayID) not found in ScreenCaptureKit content; available: \(availableIDs)")
        }

        if display.width != width || display.height != height {
            print("[INFO] ScreenCaptureKit display size is \(display.width)x\(display.height); requested \(width)x\(height)")
        }

        let cadence = CadencedFrameEncoder(encoder: encoder, fps: fps)
        let handler = ScreenCaptureFrameHandler(cadence: cadence)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false
        config.showsCursor = true
        config.queueDepth = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: handler)
        let streamQueue = DispatchQueue(label: "android-monitor.phase0.scstream.frames")

        let startSemaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        let setupQueue = DispatchQueue(label: "android-monitor.phase0.scstream.setup")

        setupQueue.async {
            do {
                try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: streamQueue)
            } catch {
                startError = error
                startSemaphore.signal()
                return
            }

            stream.startCapture { error in
                startError = error
                startSemaphore.signal()
            }
        }

        if !waitForSemaphore(startSemaphore, timeoutSeconds: 5) {
            return .failure(SpikeError.capture("ScreenCaptureKit start timed out"))
        }

        if let startError {
            return .failure(startError)
        }

        let submittedFrames = cadence.encodeForDuration(durationSeconds)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let stopSemaphore = DispatchSemaphore(value: 0)
        setupQueue.async {
            stream.stopCapture { _ in
                stopSemaphore.signal()
            }
        }
        _ = waitForSemaphore(stopSemaphore, timeoutSeconds: 3)

        let sourceFrameCount = cadence.currentSourceFrameCount()
        if sourceFrameCount > 0 && submittedFrames > sourceFrameCount {
            print("[INFO] ScreenCaptureKit submitted \(submittedFrames) encoder frames from \(sourceFrameCount) captured source frame(s)")
        }

        return .success(
            CaptureResult(
                frameCount: sourceFrameCount,
                elapsedSeconds: elapsed
            )
        )
    } catch {
        return .failure(error)
    }
}

@discardableResult
private func waitForSemaphore(_ semaphore: DispatchSemaphore, timeoutSeconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while true {
        if semaphore.wait(timeout: .now()) == .success {
            return true
        }

        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            return false
        }

        let slice = min(0.05, remaining)
        if Thread.isMainThread {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: slice))
        } else {
            Thread.sleep(forTimeInterval: slice)
        }
    }
}

func encodeSyntheticFrames(
    width: Int,
    height: Int,
    fps: Int,
    durationSeconds: TimeInterval,
    encoder: H264Encoder
) throws -> Int {
    let generator = SyntheticFrameGenerator(width: width, height: height)
    let frameTotal = max(1, Int(durationSeconds * Double(fps)))
    let frameDuration = 1.0 / Double(fps)
    let start = CFAbsoluteTimeGetCurrent()

    for frameIndex in 0..<frameTotal {
        let pixelBuffer = try generator.makeFrame(index: frameIndex)
        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
        encoder.encode(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            forceKeyframe: frameIndex == 0 || frameIndex % fps == 0
        )

        let targetElapsed = Double(frameIndex + 1) * frameDuration
        let actualElapsed = CFAbsoluteTimeGetCurrent() - start
        if actualElapsed < targetElapsed {
            Thread.sleep(forTimeInterval: targetElapsed - actualElapsed)
        }
    }

    return frameTotal
}
