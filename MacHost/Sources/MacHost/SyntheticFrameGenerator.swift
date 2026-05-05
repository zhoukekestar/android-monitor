import CoreVideo
import Foundation

final class SyntheticFrameGenerator {
    private let width: Int
    private let height: Int
    private let attributes: CFDictionary

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
    }

    func makeFrame(index: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SpikeError.encoder("CVPixelBufferCreate failed with status \(status)")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SpikeError.encoder("pixel buffer has no base address")
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let barX = (index * max(1, width / 90)) % max(1, width)
        let barHalfWidth = max(8, width / 80)
        let barStart = max(0, barX - barHalfWidth)
        let barEnd = min(width, barX + barHalfWidth)
        let barColor = bgra(red: 240, green: 196, blue: 64)

        for y in 0..<height {
            let row = baseAddress
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt32.self)
            let checker = ((y / 48) + (index / 8)) % 2
            let red = checker == 0 ? 38 : 84
            let green = y * 160 / max(1, height) + 42
            let blue = checker == 0 ? 28 : 108
            row.initialize(repeating: bgra(red: red, green: green, blue: blue), count: width)

            if barEnd > barStart {
                row.advanced(by: barStart).initialize(repeating: barColor, count: barEnd - barStart)
            }
        }

        return pixelBuffer
    }

    private func bgra(red: Int, green: Int, blue: Int) -> UInt32 {
        UInt32(255) << 24
            | UInt32(UInt8(clamping: red)) << 16
            | UInt32(UInt8(clamping: green)) << 8
            | UInt32(UInt8(clamping: blue))
    }
}
