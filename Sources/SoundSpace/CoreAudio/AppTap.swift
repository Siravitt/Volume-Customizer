import CoreAudio
import Foundation

/// Taps a set of process objects (muting their normal output) and plays the
/// tapped audio, scaled by `gain`, through a private aggregate device on the
/// default output. Torn down on deinit.
final class AppTap {
    private let tapDescription: CATapDescription
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    /// [0] = target gain written by the main thread, [1] = gain applied at the end of the last render.
    /// Allocated once so the IO thread can read it without retain/release.
    private let gainStorage: UnsafeMutablePointer<Float>

    private(set) var processes: [AudioObjectID]

    init(processes: [AudioObjectID], gain: Float) throws {
        self.processes = processes
        gainStorage = .allocate(capacity: 2)
        gainStorage.initialize(repeating: gain, count: 2)

        tapDescription = CATapDescription(stereoMixdownOfProcesses: processes)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true

        do {
            try start()
        } catch {
            stop()
            gainStorage.deallocate()
            throw error
        }
    }

    deinit {
        stop()
        gainStorage.deallocate()
    }

    var gain: Float {
        get { gainStorage[0] }
        set { gainStorage[0] = newValue }
    }

    /// Changes which processes the tap covers without rebuilding it, e.g. when
    /// Chrome spawns a new helper process.
    func update(processes newProcesses: [AudioObjectID]) throws {
        guard newProcesses != processes else { return }
        tapDescription.processes = newProcesses
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyDescription,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var description = tapDescription
        let status = withUnsafeMutablePointer(to: &description) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        try check(status, "update tap processes")
        processes = newProcesses
    }

    private func start() throws {
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")
        let tapFormat = try tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())

        let outputUID = try AudioObjectID.defaultOutputDevice().readString(kAudioDevicePropertyDeviceUID)
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sound Space",
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

        let tapChannels = Int(tapFormat.mChannelsPerFrame)
        nonisolated(unsafe) let gain = gainStorage
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                renderTap(input: input, output: output, tapChannels: tapChannels, gain: gain)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    private func stop() {
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
}
