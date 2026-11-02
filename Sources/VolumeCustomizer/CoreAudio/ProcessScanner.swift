import CoreAudio
import Darwin
import Foundation

/// Reads Core Audio's process list and resolves each process to its owning app.
enum ProcessScanner {
    static func processObjectIDs() -> [AudioObjectID] {
        (try? AudioObjectID.system.readIDs(kAudioHardwarePropertyProcessObjectList)) ?? []
    }

    static func snapshot() -> [ProcessSnapshot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processObjectIDs().compactMap { id in
            guard let pid = try? id.read(kAudioProcessPropertyPID, initial: pid_t(-1)), pid > 0, pid != ownPID else {
                return nil
            }
            let running = (try? id.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
            return ProcessSnapshot(objectID: id, isPlaying: running != 0, appBundlePath: appBundlePath(for: pid))
        }
    }

    /// The app bundle a process belongs to. Uses the "responsible" process first, so
    /// Safari's WebKit GPU process maps to Safari, then falls back to the process's own path.
    static func appBundlePath(for pid: pid_t) -> String? {
        let owner = responsiblePID(for: pid)
        if owner != pid, let path = executablePath(of: owner).flatMap(AppGrouping.outermostAppBundle) {
            return path
        }
        return executablePath(of: pid).flatMap(AppGrouping.outermostAppBundle)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<Int(length)], as: UTF8.self)
    }

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid` is private but stable (used by
    /// Activity Monitor-style tools). Looked up dynamically so a missing symbol degrades
    /// to path-based grouping instead of failing to launch.
    private static let responsibility: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let responsibility else { return pid }
        let owner = responsibility(pid)
        return owner > 0 ? owner : pid
    }
}
