import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

struct EncodedFrame {
    let data: Data
    let isKeyframe: Bool
    let presentationTimestampNs: UInt64
}

final class H264Encoder {
    private var session: VTCompressionSession?
    private let width: Int
    private let height: Int
    private let fps: Int

    var onFrame: ((EncodedFrame) -> Void)?

    init(width: Int, height: Int, fps: Int, bitrateMbps: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps
        try setupSession(bitrateMbps: bitrateMbps)
    }

    func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, forceKeyframe: Bool = false) {
        guard let session else {
            return
        }

        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        var frameProperties: CFDictionary?
        if forceKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    func finish() {
        guard let session else {
            return
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    func updateBitrateMbps(_ bitrateMbps: Int) {
        guard let session else {
            return
        }
        setBitrate(on: session, bitrateMbps: bitrateMbps)
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    private func setupSession(bitrateMbps: Int) throws {
        let imageAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]

        var createdSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: imageAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: h264EncodingCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )

        guard status == noErr, let createdSession else {
            throw SpikeError.encoder("VTCompressionSessionCreate failed with status \(status)")
        }

        session = createdSession

        setSessionProperty(createdSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        setSessionProperty(createdSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel)
        setBitrate(on: createdSession, bitrateMbps: bitrateMbps)
        setSessionProperty(createdSession, kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        setSessionProperty(createdSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, fps as CFNumber)
        setSessionProperty(createdSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 1 as CFNumber)
        setSessionProperty(createdSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(createdSession)
        guard prepareStatus == noErr else {
            throw SpikeError.encoder("VTCompressionSessionPrepareToEncodeFrames failed with status \(prepareStatus)")
        }
    }

    private func setSessionProperty(_ session: VTCompressionSession, _ key: CFString, _ value: CFTypeRef) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            print("[WARN] VTSessionSetProperty \(key) failed: \(status)")
        }
    }

    private func setBitrate(on session: VTCompressionSession, bitrateMbps: Int) {
        let bitsPerSecond = bitrateMbps * 1_000_000
        let bytesPerSecond = bitrateMbps * 125_000
        setSessionProperty(session, kVTCompressionPropertyKey_AverageBitRate, bitsPerSecond as CFNumber)
        setSessionProperty(
            session,
            kVTCompressionPropertyKey_DataRateLimits,
            [bytesPerSecond as CFNumber, 1 as CFNumber] as CFArray
        )
    }
}

private let annexBStartCode: [UInt8] = [0, 0, 0, 1]

private let h264EncodingCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard status == noErr,
          let sampleBuffer,
          let refcon,
          let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        return
    }

    let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
    let isKeyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)

    var lengthAtOffset = 0
    var totalLength = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let blockStatus = CMBlockBufferGetDataPointer(
        dataBuffer,
        atOffset: 0,
        lengthAtOffsetOut: &lengthAtOffset,
        totalLengthOut: &totalLength,
        dataPointerOut: &dataPointer
    )
    guard blockStatus == kCMBlockBufferNoErr, let dataPointer else {
        return
    }

    var frameData = Data(capacity: totalLength + 128)
    if isKeyframe, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
        appendH264ParameterSets(from: formatDescription, to: &frameData)
    }

    var offset = 0
    while offset + 4 <= totalLength {
        var nalLength: UInt32 = 0
        memcpy(&nalLength, dataPointer.advanced(by: offset), 4)
        nalLength = UInt32(bigEndian: nalLength)
        offset += 4

        let end = offset + Int(nalLength)
        guard end <= totalLength else {
            return
        }

        frameData.append(contentsOf: annexBStartCode)
        let nalPointer = UnsafeRawPointer(dataPointer.advanced(by: offset)).assumingMemoryBound(to: UInt8.self)
        frameData.append(nalPointer, count: Int(nalLength))
        offset = end
    }

    let ptsSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    let ptsNs = ptsSeconds.isFinite && ptsSeconds >= 0 ? UInt64(ptsSeconds * 1_000_000_000) : 0
    encoder.onFrame?(
        EncodedFrame(
            data: frameData,
            isKeyframe: isKeyframe,
            presentationTimestampNs: ptsNs
        )
    )
}

private func appendH264ParameterSets(from formatDescription: CMFormatDescription, to data: inout Data) {
    var parameterSetCount = 0
    let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        parameterSetIndex: 0,
        parameterSetPointerOut: nil,
        parameterSetSizeOut: nil,
        parameterSetCountOut: &parameterSetCount,
        nalUnitHeaderLengthOut: nil
    )
    guard countStatus == noErr else {
        return
    }

    for index in 0..<parameterSetCount {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let pointer else {
            continue
        }
        data.append(contentsOf: annexBStartCode)
        data.append(pointer, count: size)
    }
}
