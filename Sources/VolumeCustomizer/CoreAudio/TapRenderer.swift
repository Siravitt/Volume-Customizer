import CoreAudio

/// Copies the tap's channels (the last `tapChannels` input channels) to the first
/// output channels, ramping gain from gain[1] to gain[0] across the buffer.
/// Output channels beyond the tap's channels are silenced.
///
/// Real-time thread: no allocation, locks, logging, or object references.
func renderTap(
    input: UnsafePointer<AudioBufferList>,
    output: UnsafeMutablePointer<AudioBufferList>,
    tapChannels: Int,
    gain: UnsafeMutablePointer<Float>
) {
    let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    let outputs = UnsafeMutableAudioBufferListPointer(output)

    var totalInputChannels = 0
    for buffer in inputs { totalInputChannels += Int(buffer.mNumberChannels) }
    let tapStart = totalInputChannels - tapChannels

    let startGain = gain[1]
    let targetGain = gain[0]
    var outputChannel = 0

    for buffer in outputs {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0 else { continue }
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)

        for channel in 0..<channels {
            let tapChannel = outputChannel + channel
            var written = 0
            if tapStart >= 0, tapChannel < tapChannels,
               let source = channelSamples(inputs, channel: tapStart + tapChannel) {
                written = min(frames, source.frames)
                let step = (targetGain - startGain) / Float(max(written, 1))
                var g = startGain
                for frame in 0..<written {
                    g += step
                    let sample = source.data[frame * source.stride] * g
                    data[frame * channels + channel] = min(max(sample, -1), 1)
                }
            }
            for frame in written..<frames { data[frame * channels + channel] = 0 }
        }
        outputChannel += channels
    }
    gain[1] = targetGain
}

/// Locates channel `channel` (counted across all buffers) in an interleaved or
/// non-interleaved Float32 buffer list.
private func channelSamples(
    _ list: UnsafeMutableAudioBufferListPointer,
    channel: Int
) -> (data: UnsafeMutablePointer<Float>, stride: Int, frames: Int)? {
    var first = 0
    for buffer in list {
        let channels = Int(buffer.mNumberChannels)
        if channel < first + channels {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            return (data + (channel - first), channels, frames)
        }
        first += channels
    }
    return nil
}
