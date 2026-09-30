import CoreAudio
import Testing
@testable import SoundSpace

/// Owns an AudioBufferList of Float32 buffers with the given channel counts.
private final class TestBuffers {
    let list: UnsafeMutableAudioBufferListPointer
    let channels: [Int]
    let frames: Int

    init(channels: [Int], frames: Int) {
        self.channels = channels
        self.frames = frames
        list = AudioBufferList.allocate(maximumBuffers: channels.count)
        for (index, count) in channels.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: count * frames)
            data.initialize(repeating: 0, count: count * frames)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(count),
                mDataByteSize: UInt32(count * frames * MemoryLayout<Float>.size),
                mData: data
            )
        }
    }

    deinit {
        for buffer in list { buffer.mData?.deallocate() }
        free(list.unsafeMutablePointer)
    }

    subscript(buffer: Int, frame: Int, channel: Int) -> Float {
        get { list[buffer].mData!.assumingMemoryBound(to: Float.self)[frame * channels[buffer] + channel] }
        set { list[buffer].mData!.assumingMemoryBound(to: Float.self)[frame * channels[buffer] + channel] = newValue }
    }
}

private func render(_ input: TestBuffers, _ output: TestBuffers, tapChannels: Int = 2, gain: (start: Float, target: Float)) -> Float {
    let storage = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    defer { storage.deallocate() }
    storage[0] = gain.target
    storage[1] = gain.start
    renderTap(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, tapChannels: tapChannels, gain: storage)
    return storage[1]
}

struct TapRendererTests {
    @Test func scalesInterleavedStereo() {
        let input = TestBuffers(channels: [2], frames: 4)
        let output = TestBuffers(channels: [2], frames: 4)
        for frame in 0..<4 {
            input[0, frame, 0] = 0.8
            input[0, frame, 1] = -0.4
        }

        _ = render(input, output, gain: (0.5, 0.5))

        for frame in 0..<4 {
            #expect(output[0, frame, 0] == 0.4)
            #expect(output[0, frame, 1] == -0.2)
        }
    }

    @Test func readsTapFromLastInputChannels() {
        // Aggregate input = [device mic (2ch), tap (2ch)]
        let input = TestBuffers(channels: [2, 2], frames: 2)
        let output = TestBuffers(channels: [2], frames: 2)
        for frame in 0..<2 {
            input[0, frame, 0] = 0.9
            input[1, frame, 0] = 0.1
            input[1, frame, 1] = 0.2
        }

        _ = render(input, output, gain: (1, 1))

        #expect(output[0, 0, 0] == 0.1)
        #expect(output[0, 0, 1] == 0.2)
    }

    @Test func writesNonInterleavedOutput() {
        let input = TestBuffers(channels: [2], frames: 2)
        let output = TestBuffers(channels: [1, 1], frames: 2)
        input[0, 1, 0] = 0.3
        input[0, 1, 1] = 0.6

        _ = render(input, output, gain: (1, 1))

        #expect(output[0, 1, 0] == 0.3)
        #expect(output[1, 1, 0] == 0.6)
    }

    @Test func silencesExtraOutputChannels() {
        let input = TestBuffers(channels: [2], frames: 2)
        let output = TestBuffers(channels: [4], frames: 2)
        output[0, 0, 3] = 0.7
        input[0, 0, 0] = 0.5

        _ = render(input, output, gain: (1, 1))

        #expect(output[0, 0, 0] == 0.5)
        #expect(output[0, 0, 3] == 0)
    }

    @Test func clampsToFullScale() {
        let input = TestBuffers(channels: [2], frames: 1)
        let output = TestBuffers(channels: [2], frames: 1)
        input[0, 0, 0] = 0.8
        input[0, 0, 1] = -0.8

        _ = render(input, output, gain: (2, 2))

        #expect(output[0, 0, 0] == 1)
        #expect(output[0, 0, 1] == -1)
    }

    @Test func rampsGainAcrossBufferAndRemembersIt() {
        let input = TestBuffers(channels: [2], frames: 4)
        let output = TestBuffers(channels: [2], frames: 4)
        for frame in 0..<4 { input[0, frame, 0] = 1 }

        let applied = render(input, output, gain: (0, 1))

        #expect(output[0, 0, 0] == 0.25)
        #expect(output[0, 1, 0] == 0.5)
        #expect(output[0, 3, 0] == 1)
        #expect(applied == 1)
    }
}
