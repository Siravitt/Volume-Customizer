import AppKit
import CoreAudio

struct AppSetting: Equatable {
    var volume: Double = 1
    var isMuted = false

    /// Apps at 100% and unmuted are left alone: no tap, no added latency.
    var needsTap: Bool { isMuted || volume != 1 }
    var gain: Float { isMuted ? 0 : Float(volume) }
}

struct AudioApp: Identifiable {
    /// Bundle identifier, or the bundle path when the app has none.
    let id: String
    let name: String
    let icon: NSImage
    let processObjectIDs: [AudioObjectID]
    let isPlaying: Bool
}

/// Owns the visible app list, per-app settings, and the taps that enforce them.
@MainActor
@Observable
final class Mixer {
    private(set) var apps: [AudioApp] = []
    private(set) var settings: [String: AppSetting] = [:]
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private var taps: [String: AppTap] = [:]
    @ObservationIgnored private var pendingReleases: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var bundleInfo: [String: (id: String, name: String, icon: NSImage)] = [:]
    @ObservationIgnored private let monitor = ProcessMonitor()

    /// How long an app must sit at 100% before its tap is removed, so dragging
    /// the slider across 100% doesn't rebuild the tap repeatedly.
    private static let releaseDelay: Duration = .seconds(1)

    init() {
        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        refresh()
    }

    func setting(for id: AudioApp.ID) -> AppSetting {
        settings[id] ?? AppSetting()
    }

    func setVolume(_ volume: Double, for id: AudioApp.ID) {
        settings[id, default: AppSetting()].volume = volume
        apply(id)
    }

    func toggleMute(for id: AudioApp.ID) {
        settings[id, default: AppSetting()].isMuted.toggle()
        apply(id)
    }

    func refresh() {
        let groups = AppGrouping.group(ProcessScanner.snapshot())
        var runningApps: [AudioApp] = []
        for group in groups {
            let info = info(forBundleAt: group.bundlePath)
            runningApps.append(AudioApp(
                id: info.id,
                name: info.name,
                icon: info.icon,
                processObjectIDs: group.processObjectIDs,
                isPlaying: group.isPlaying
            ))
        }

        for (id, tap) in taps {
            guard let app = runningApps.first(where: { $0.id == id }) else {
                // App quit: its process objects are gone.
                releaseTap(id)
                continue
            }
            do {
                try tap.update(processes: app.processObjectIDs)
            } catch {
                errors[id] = "\(error)"
            }
        }

        apps = runningApps
            .filter { $0.isPlaying || taps[$0.id] != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        log.debug("refresh: \(self.apps.map(\.name), privacy: .public)")
    }

    func releaseAllTaps() {
        for id in Array(taps.keys) { releaseTap(id) }
    }

    private func apply(_ id: AudioApp.ID) {
        let setting = setting(for: id)
        guard setting.needsTap else {
            guard let tap = taps[id], pendingReleases[id] == nil else { return }
            tap.gain = 1
            pendingReleases[id] = Task { [weak self] in
                try? await Task.sleep(for: Self.releaseDelay)
                guard !Task.isCancelled else { return }
                self?.releaseTap(id)
                self?.refresh()
            }
            return
        }

        pendingReleases[id]?.cancel()
        pendingReleases[id] = nil
        if let tap = taps[id] {
            tap.gain = setting.gain
            return
        }
        guard let app = apps.first(where: { $0.id == id }) else { return }
        do {
            taps[id] = try AppTap(processes: app.processObjectIDs, gain: setting.gain)
            errors[id] = nil
        } catch {
            errors[id] = "\(error)"
        }
    }

    private func releaseTap(_ id: AudioApp.ID) {
        pendingReleases[id]?.cancel()
        pendingReleases[id] = nil
        taps[id] = nil
    }

    private func info(forBundleAt path: String) -> (id: String, name: String, icon: NSImage) {
        if let cached = bundleInfo[path] { return cached }
        let bundle = Bundle(path: path)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        let info = (id: bundle?.bundleIdentifier ?? path, name: name, icon: NSWorkspace.shared.icon(forFile: path))
        bundleInfo[path] = info
        return info
    }
}
