import AppKit
import CoreAudio

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let context: String

    var description: String { "\(context) failed: OSStatus \(status) \(fourCC(UInt32(bitPattern: status)))" }
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "" }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
}

func check(_ status: OSStatus, _ context: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, context: context()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: T
    ) throws -> T {
        var addr = address(selector, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(self, &addr, 0, nil, &size, $0) }
        try check(status, "read \(fourCC(selector))")
        return value
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector, kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &value), "read \(fourCC(selector))")
        return value?.takeRetainedValue() as String? ?? ""
    }

    func readIDs(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var addr = address(selector, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "size of \(fourCC(selector))")
        var ids = [AudioObjectID](repeating: .unknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &ids), "read \(fourCC(selector))")
        return ids
    }

    /// Channel count of each buffer in the device's stream configuration for `scope`.
    func streamChannels(scope: AudioObjectPropertyScope) throws -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "size of stream configuration")
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, raw), "read stream configuration")
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    static func defaultOutputDevice() throws -> AudioObjectID {
        try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)
    }
}

/// A process that Core Audio knows about (has an audio client).
struct AudioProcess: Identifiable, Hashable {
    let id: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let name: String
    let isPlaying: Bool

    static func all() throws -> [AudioProcess] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return try AudioObjectID.system.readIDs(kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid = try? id.read(kAudioProcessPropertyPID, initial: pid_t(-1)), pid != ownPID else { return nil }
            let bundleID = (try? id.readString(kAudioProcessPropertyBundleID)) ?? ""
            let running = (try? id.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? (bundleID.isEmpty ? "pid \(pid)" : bundleID)
            return AudioProcess(id: id, pid: pid, bundleID: bundleID, name: name, isPlaying: running != 0)
        }
    }
}
