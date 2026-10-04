import CoreMedia
import Foundation
import ViewportProtocol

/// One decodable H.264 access unit, ready for `AVSampleBufferDisplayLayer` / VideoToolbox.
public struct VideoFrame: @unchecked Sendable {
    public let sample: CMSampleBuffer
    public let epoch: UInt32
    public let width: Int
    public let height: Int
    public let isKeyframe: Bool
    public let captureTimeNanos: UInt64
    /// True on the first frame of a new format (epoch, size, or parameter sets changed).
    public let formatChanged: Bool
}

/// T1-GFX-07 client side: turns `VideoPacket`s into `CMSampleBuffer`s marked for immediate display.
/// Drops delta frames until it has a keyframe for the current epoch.
public struct H264SampleBuilder: Sendable {
    public enum Output {
        case frame(VideoFrame)
        /// Cannot decode yet; ask the host for a keyframe.
        case needKeyframe
    }

    private nonisolated(unsafe) var format: CMVideoFormatDescription?
    private var epoch: UInt32?
    private var parameterSets: [Data] = []

    public init() {}

    public mutating func make(_ packet: VideoPacket) -> Output {
        var formatChanged = false
        if packet.epoch != epoch {
            epoch = packet.epoch
            format = nil
            parameterSets = []
        }
        if packet.isKeyframe, packet.parameterSets.count >= 2, packet.parameterSets != parameterSets {
            guard let f = Self.formatDescription(packet.parameterSets) else { return .needKeyframe }
            format = f
            parameterSets = packet.parameterSets
            formatChanged = true
        }
        guard let format else { return .needKeyframe }
        guard let sample = Self.sampleBuffer(packet.avcc, format: format, isKeyframe: packet.isKeyframe) else {
            return .needKeyframe
        }
        return .frame(
            VideoFrame(
                sample: sample, epoch: packet.epoch, width: Int(packet.width), height: Int(packet.height),
                isKeyframe: packet.isKeyframe, captureTimeNanos: packet.captureTimeNanos, formatChanged: formatChanged))
    }

    static func formatDescription(_ sets: [Data]) -> CMVideoFormatDescription? {
        let pointers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { pointers.forEach { $0.deallocate() } }
        let sizes = sets.map(\.count)
        var format: CMVideoFormatDescription?
        let status = pointers.map { UnsafePointer($0) }.withUnsafeBufferPointer { ptrs in
            sizes.withUnsafeBufferPointer { lens in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: ptrs.baseAddress!,
                    parameterSetSizes: lens.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        return status == noErr ? format : nil
    }

    static func sampleBuffer(_ avcc: Data, format: CMVideoFormatDescription, isKeyframe: Bool) -> CMSampleBuffer? {
        guard !avcc.isEmpty else { return nil }
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block) == noErr, let block
        else { return nil }
        let copied = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = avcc.count
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size,
                sampleBufferOut: &sample) == noErr, let sample
        else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0
        {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            if !isKeyframe {
                CFDictionarySetValue(
                    dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return sample
    }
}
