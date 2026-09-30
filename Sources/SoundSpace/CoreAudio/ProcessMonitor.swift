import CoreAudio
import Foundation

/// Calls `onChange` (coalesced) when processes appear/disappear or start/stop playing.
@MainActor
final class ProcessMonitor {
    var onChange: (() -> Void)?

    private var processListListener: AudioObjectPropertyListenerBlock?
    private var runningListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingChange: Task<Void, Never>?

    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningOutput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        let listener = makeListener()
        AudioObjectAddPropertyListenerBlock(.system, &Self.processListAddress, .main, listener)
        processListListener = listener
        syncRunningListeners()
    }

    private func makeListener() -> AudioObjectPropertyListenerBlock {
        { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleChange() }
        }
    }

    private func handleChange() {
        log.debug("process change notification")
        syncRunningListeners()
        pendingChange?.cancel()
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    private func syncRunningListeners() {
        let current = Set(ProcessScanner.processObjectIDs())
        for (id, listener) in runningListeners where !current.contains(id) {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningAddress, .main, listener)
            runningListeners[id] = nil
        }
        for id in current where runningListeners[id] == nil {
            let listener = makeListener()
            if AudioObjectAddPropertyListenerBlock(id, &Self.runningAddress, .main, listener) == noErr {
                runningListeners[id] = listener
            }
        }
    }
}
