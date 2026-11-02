import AudioToolbox
import CoreAudio

/// Volume and mute of the system default output device, kept in sync with
/// changes made elsewhere (volume keys, Control Center, device switches).
@MainActor
@Observable
final class SystemVolume {
    private(set) var deviceName = ""
    private(set) var canSetVolume = false
    private(set) var volume: Double = 0
    private(set) var canMute = false
    private(set) var isMuted = false

    @ObservationIgnored private var device = AudioObjectID.unknown
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private static let outputScope = kAudioDevicePropertyScopeOutput

    func start() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        attachToDefaultDevice()
    }

    func setVolume(_ value: Double) {
        volume = value
        try? device.write(Self.volumeSelector, scope: Self.outputScope, value: Float32(value))
    }

    func toggleMute() {
        try? device.write(kAudioDevicePropertyMute, scope: Self.outputScope, value: UInt32(isMuted ? 0 : 1))
        readState()
    }

    private func attachToDefaultDevice() {
        for (address, listener) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
        deviceListeners = []

        device = (try? AudioObjectID.defaultOutputDevice()) ?? .unknown
        deviceName = (try? device.readString(kAudioObjectPropertyName)) ?? ""

        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: Self.outputScope,
                mElement: kAudioObjectPropertyElementMain
            )
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.readState() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
                deviceListeners.append((address, listener))
            }
        }
        readState()
    }

    private func readState() {
        canSetVolume = device.isSettable(Self.volumeSelector, scope: Self.outputScope)
        volume = Double((try? device.read(Self.volumeSelector, scope: Self.outputScope, initial: Float32(0))) ?? 0)
        canMute = device.isSettable(kAudioDevicePropertyMute, scope: Self.outputScope)
        isMuted = ((try? device.read(kAudioDevicePropertyMute, scope: Self.outputScope, initial: UInt32(0))) ?? 0) != 0
    }
}
