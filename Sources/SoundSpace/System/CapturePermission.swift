import AppKit
import Foundation

enum CapturePermissionStatus {
    case authorized, denied, notDetermined
    /// The private TCC API couldn't be loaded; fall back to letting the system prompt on first tap.
    case unknown

    var allowsCapture: Bool { self == .authorized || self == .unknown }
}

/// Status of the "audio capture" (system audio recording) permission.
///
/// There is no public API to check it, so this uses the private TCC functions
/// `TCCAccessPreflight` / `TCCAccessRequest`, loaded dynamically so a missing
/// symbol degrades to `.unknown` instead of crashing.
@MainActor
@Observable
final class CapturePermission {
    private(set) var status: CapturePermissionStatus = .unknown

    func refresh() {
        status = Self.preflight()
    }

    func request() async {
        guard let requestAccess = Self.requestFunction else {
            refresh()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestAccess(Self.service, nil) { _ in continuation.resume() }
        }
        refresh()
    }

    /// Opens the Privacy pane that lists apps allowed to record system audio.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private static let service = "kTCCServiceAudioCapture" as CFString

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @convention(block) @Sendable (Bool) -> Void) -> Void

    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflightFunction: PreflightFunction? = {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    private static let requestFunction: RequestFunction? = {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()

    private static func preflight() -> CapturePermissionStatus {
        guard let preflightFunction else { return .unknown }
        switch preflightFunction(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        case 2: return .notDetermined
        default: return .unknown
        }
    }
}
