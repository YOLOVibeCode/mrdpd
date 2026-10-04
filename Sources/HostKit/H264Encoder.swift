import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import ViewportProtocol

public struct EncodedFrame: Sendable {
    public let isKeyframe: Bool
    /// SPS then PPS on keyframes.
    public let parameterSets: [Data]
    /// 4-byte length-prefixed NAL units.
    public let avcc: Data
    public let hostNanos: UInt64
}

public enum EncoderError: Error {
    case create(OSStatus)
}

/// T1-GFX-07: VideoToolbox H.264 with the spike R15 settings — real time, no frame reordering,
/// low-latency rate control, no frame delay, speed over quality.
public final class H264Encoder: @unchecked Sendable {
    public let size: PixelSize
    private let session: VTCompressionSession
    private let lock = NSLock()
    private var invalid = false

    public init(size: PixelSize, fps: Int, allowSoftware: Bool = false) throws {
        self.size = size
        var spec: [CFString: Any] = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true]
        if allowSoftware {
            spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
        } else {
            spec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
        }
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(size.width), height: Int32(size.height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let s else { throw EncoderError.create(status) }
        session = s
        let set = { (key: CFString, value: CFTypeRef) in _ = VTSessionSetProperty(s, key: key, value: value) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_MaxFrameDelayCount, 0 as CFNumber)
        set(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 30 as CFNumber)
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        apply(fps: fps)
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    deinit {
        VTCompressionSessionInvalidate(session)
    }

    /// ~0.08 bits per pixel per frame: 28 Mbit/s for an iPad-13" viewport at 60 fps.
    public static func bitrate(size: PixelSize, fps: Int) -> Int {
        min(40_000_000, max(2_000_000, size.pixels * max(fps, 1) / 12))
    }

    public func setFrameRate(_ fps: Int) {
        apply(fps: fps)
    }

    private func apply(fps: Int) {
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(
            session, key: kVTCompressionPropertyKey_AverageBitRate, value: Self.bitrate(size: size, fps: fps) as CFNumber)
    }

    /// `completion` gets nil when the frame was dropped or failed.
    public func encode(
        _ pixelBuffer: CVPixelBuffer, hostNanos: UInt64, forceKeyframe: Bool,
        completion: @escaping @Sendable (EncodedFrame?) -> Void
    ) {
        guard !lock.withLock({ invalid }) else {
            completion(nil)
            return
        }
        let props = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: CMTimeValue(hostNanos), timescale: 1_000_000_000),
            duration: .invalid, frameProperties: props, infoFlagsOut: nil
        ) { status, flags, sample in
            guard status == noErr, !flags.contains(.frameDropped), let sample else {
                completion(nil)
                return
            }
            completion(Self.extract(sample, hostNanos: hostNanos))
        }
        if status != noErr { completion(nil) }
    }

    public func invalidate() {
        lock.withLock { invalid = true }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    static func extract(_ sample: CMSampleBuffer, hostNanos: UInt64) -> EncodedFrame? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool
        {
            isKeyframe = !notSync
        }
        var sets: [Data] = []
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var ptr: UnsafePointer<UInt8>?
                var len = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: i, parameterSetPointerOut: &ptr, parameterSetSizeOut: &len,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let ptr
                {
                    sets.append(Data(bytes: ptr, count: len))
                }
            }
        }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let copied = data.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard copied == noErr else { return nil }
        return EncodedFrame(isKeyframe: isKeyframe, parameterSets: sets, avcc: data, hostNanos: hostNanos)
    }
}
