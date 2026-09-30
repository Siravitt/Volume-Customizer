import AppKit
import CoreAudio

struct AudioApp: Identifiable {
    /// Bundle identifier, or the bundle path when the app has none.
    let id: String
    let name: String
    let icon: NSImage
    let processObjectIDs: [AudioObjectID]
    let isPlaying: Bool
}

/// Owns the visible app list, per-app settings, and the taps that enforce them.
///
/// A running app with a non-default setting is tapped for as long as it runs, not
/// only while it plays, so its first sound isn't heard at full volume.
@MainActor
@Observable
final class Mixer {
    private(set) var apps: [AudioApp] = []
    private(set) var settings: [String: AppSetting]
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private var runningApps: [String: AudioApp] = [:]
    @ObservationIgnored private var stoppedAt: [String: Date] = [:]
    @ObservationIgnored private var taps: [String: AppTap] = [:]
    @ObservationIgnored private var pendingReleases: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lingerRefresh: Task<Void, Never>?
    @ObservationIgnored private var bundleInfo: [String: (id: String, name: String, icon: NSImage)] = [:]
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let monitor = AudioSystemMonitor()

    /// How long an app must sit at 100% before its tap is removed, so dragging
    /// the slider across 100% doesn't rebuild the tap repeatedly.
    private static let releaseDelay: Duration = .seconds(1)

    /// `active: false` builds an inert mixer (used when the app is only a unit-test host).
    init(store: SettingsStore = SettingsStore(), active: Bool = true) {
        self.store = store
        settings = active ? store.load() : [:]
        guard active else { return }
        monitor.onProcessesChange = { [weak self] in self?.refresh() }
        monitor.onDefaultOutputChange = { [weak self] in self?.rebuildTaps() }
        monitor.start()
        refresh()
    }

    func setting(for id: AudioApp.ID) -> AppSetting {
        settings[id] ?? AppSetting()
    }

    func setVolume(_ volume: Double, for id: AudioApp.ID) {
        settings[id, default: AppSetting()].volume = volume
        settingChanged(id)
    }

    func toggleMute(for id: AudioApp.ID) {
        settings[id, default: AppSetting()].isMuted.toggle()
        settingChanged(id)
    }

    func refresh() {
        let now = Date()
        var latest: [String: AudioApp] = [:]
        for group in AppGrouping.group(ProcessScanner.snapshot()) {
            let info = info(forBundleAt: group.bundlePath)
            latest[info.id] = AudioApp(
                id: info.id,
                name: info.name,
                icon: info.icon,
                processObjectIDs: group.processObjectIDs,
                isPlaying: group.isPlaying
            )
        }

        for (id, app) in latest {
            if app.isPlaying {
                stoppedAt[id] = nil
            } else if runningApps[id]?.isPlaying == true {
                stoppedAt[id] = now
            }
        }
        for id in runningApps.keys where latest[id] == nil {
            // App quit.
            stoppedAt[id] = nil
            errors[id] = nil
            releaseTap(id)
        }
        runningApps = latest
        stoppedAt = stoppedAt.filter { now.timeIntervalSince($0.value) < AppListPolicy.linger }

        for (id, app) in latest {
            if let tap = taps[id] {
                do {
                    try tap.update(processes: app.processObjectIDs)
                } catch {
                    errors[id] = "\(error)"
                }
            } else if setting(for: id).needsTap, errors[id] == nil {
                createTap(for: app)
            }
        }

        apps = latest.values
            .filter {
                AppListPolicy.isVisible(
                    isPlaying: $0.isPlaying,
                    hasCustomSetting: taps[$0.id] != nil || setting(for: $0.id).needsTap,
                    stoppedAt: stoppedAt[$0.id],
                    now: now
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        log.debug("refresh: \(self.apps.map(\.name), privacy: .public)")
        scheduleLingerRefresh(now: now)
    }

    /// Recreates every tap on the current default output device.
    func rebuildTaps() {
        log.debug("rebuilding \(self.taps.count) taps for new output device")
        for id in Array(taps.keys) {
            releaseTap(id)
            errors[id] = nil
        }
        refresh()
    }

    private func settingChanged(_ id: AudioApp.ID) {
        store.save(settings)
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
        } else if let app = runningApps[id] {
            createTap(for: app)
        }
    }

    private func createTap(for app: AudioApp) {
        do {
            taps[app.id] = try AppTap(processes: app.processObjectIDs, gain: setting(for: app.id).gain)
            errors[app.id] = nil
        } catch {
            log.error("tap failed for \(app.id, privacy: .public): \(String(describing: error), privacy: .public)")
            errors[app.id] = "\(error)"
        }
    }

    private func releaseTap(_ id: AudioApp.ID) {
        pendingReleases[id]?.cancel()
        pendingReleases[id] = nil
        taps[id] = nil
    }

    /// Refreshes again when the soonest lingering row should disappear.
    private func scheduleLingerRefresh(now: Date) {
        lingerRefresh?.cancel()
        guard let soonest = stoppedAt.values.min() else { return }
        let delay = max(soonest.addingTimeInterval(AppListPolicy.linger).timeIntervalSince(now), 0) + 0.1
        lingerRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
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
