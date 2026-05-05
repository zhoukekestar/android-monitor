import Foundation

final class AdaptiveBitrateController {
    private let fps: Int
    private let minimumBitrateMbps: Int
    private var currentBitrateMbps: Int
    private var lastAdjustmentDecodedFrames = 0

    init(fps: Int, initialBitrateMbps: Int, minimumBitrateMbps: Int = 1) {
        self.fps = fps
        self.currentBitrateMbps = initialBitrateMbps
        self.minimumBitrateMbps = minimumBitrateMbps
    }

    func handle(stats: AndroidStreamStats, encoder: H264Encoder) {
        guard currentBitrateMbps > minimumBitrateMbps else {
            return
        }

        let totalFrames = stats.decodedFrames + stats.droppedFrames
        guard totalFrames >= max(30, fps * 2) else {
            return
        }

        let framesSinceAdjustment = stats.decodedFrames - lastAdjustmentDecodedFrames
        guard framesSinceAdjustment >= max(15, fps * 5) else {
            return
        }

        let dropRatio = Double(stats.droppedFrames) / Double(max(totalFrames, 1))
        let lowInputFps = stats.inputFps > 0 && stats.inputFps < Double(fps) * 0.70
        guard dropRatio >= 0.08 || lowInputFps else {
            return
        }

        let nextBitrate = max(minimumBitrateMbps, Int(Double(currentBitrateMbps) * 0.75))
        guard nextBitrate < currentBitrateMbps else {
            return
        }

        currentBitrateMbps = nextBitrate
        lastAdjustmentDecodedFrames = stats.decodedFrames
        encoder.updateBitrateMbps(nextBitrate)
        print(
            String(
                format: "[INFO] Adaptive bitrate lowered to %d Mbps (drop_ratio=%.2f input=%.1f fps)",
                nextBitrate,
                dropRatio,
                stats.inputFps
            )
        )
    }
}
