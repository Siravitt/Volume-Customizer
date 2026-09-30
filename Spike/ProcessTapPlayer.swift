import CoreAudio
import Foundation

/// Taps one process (muting its normal output) and plays the tapped audio,
/// scaled by `gain`, through a private aggregate device on the default output.
final class ProcessTapPlayer {
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    /// [0] = target gain written by the UI, [1] = gain applied at the end of the last render.
    /// Allocated once so the IO thread can read it without retain/release.
    private let gain: UnsafeMutablePointer<Float>

    init() {
        gain = .allocate(capacity: 2)
        gain.initialize(repeating: 1, count: 2)
    }

    deinit {
        stop()
        gain.deallocate()
    }

    var targetGain: Float {
        get { gain[0] }
        set { gain[0] = newValue }
    }

    var isRunning: Bool { ioProcID != nil }

    /// Starts tapping and returns human-readable diagnostics about the setup.
    func start(process: AudioProcess) throws -> [String] {
        stop()
        do {
            return try setUp(process: process)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    private func setUp(process: AudioProcess) throws -> [String] {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [process.id])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")

        let tapFormat = try tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())

        let outputDevice = try AudioObjectID.defaultOutputDevice()
        let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let outputName = (try? outputDevice.readString(kAudioObjectPropertyName)) ?? outputUID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sound Space Spike",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice"
        )

        let inputChannels = try aggregateID.streamChannels(scope: kAudioObjectPropertyScopeInput)
        let outputChannels = try aggregateID.streamChannels(scope: kAudioObjectPropertyScopeOutput)
        let sampleRate = try aggregateID.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(0))

        let tapChannels = Int(tapFormat.mChannelsPerFrame)
        gain[1] = gain[0]
        nonisolated(unsafe) let gain = gain
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                renderTap(input: input, output: output, tapChannels: tapChannels, gain: gain)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")

        return [
            "process: \(process.name) (\(process.bundleID), pid \(process.pid), object \(process.id))",
            "tap format: \(tapFormat.mSampleRate) Hz, \(tapChannels) ch, flags \(tapFormat.mFormatFlags)",
            "output: \(outputName)",
            "aggregate: \(sampleRate) Hz, input buffers \(inputChannels), output buffers \(outputChannels)",
        ]
    }
}

/// Copies the tap's channels (the last `tapChannels` input channels) to the first
/// output channels, ramping gain from gain[1] to gain[0] across the buffer.
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
