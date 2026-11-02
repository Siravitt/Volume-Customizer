import CoreAudio
import Foundation

/// Watches Core Audio for changes the mixer cares about. Callbacks are coalesced
/// because Core Audio often fires several notifications for one change.
@MainActor
final class AudioSystemMonitor {
    /// Processes appeared/disappeared or started/stopped playing.
    var onProcessesChange: (() -> Void)?
    /// The system default output device changed (e.g. AirPods connected).
    var onDefaultOutputChange: (() -> Void)?

    private var runningListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingProcessChange: Task<Void, Never>?
    private var pendingOutputChange: Task<Void, Never>?

    private static var processListAddress = globalAddress(kAudioHardwarePropertyProcessObjectList)
    private static var runningAddress = globalAddress(kAudioProcessPropertyIsRunningOutput)
    private static var defaultOutputAddress = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)

    func start() {
        let processListener = makeListener { $0.handleProcessChange() }
        AudioObjectAddPropertyListenerBlock(.system, &Self.processListAddress, .main, processListener)
        let outputListener = makeListener { $0.handleOutputChange() }
        AudioObjectAddPropertyListenerBlock(.system, &Self.defaultOutputAddress, .main, outputListener)
        syncRunningListeners()
    }

    private func makeListener(_ handler: @escaping (AudioSystemMonitor) -> Void) -> AudioObjectPropertyListenerBlock {
        { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
    }

    private func handleProcessChange() {
        log.debug("process change notification")
        syncRunningListeners()
        pendingProcessChange?.cancel()
        pendingProcessChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.onProcessesChange?()
        }
    }

    private func handleOutputChange() {
        log.debug("default output change notification")
        pendingOutputChange?.cancel()
        pendingOutputChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.onDefaultOutputChange?()
        }
    }

    private func syncRunningListeners() {
        let current = Set(ProcessScanner.processObjectIDs())
        for (id, listener) in runningListeners where !current.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningAddress, .main, listener)
            runningListeners[id] = nil
        }
        for id in current where runningListeners[id] == nil {
            let listener = makeListener { $0.handleProcessChange() }
            if AudioObjectAddPropertyListenerBlock(id, &Self.runningAddress, .main, listener) == noErr {
                runningListeners[id] = listener
            }
        }
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
