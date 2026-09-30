import Foundation

struct AppSetting: Equatable, Codable {
    var volume: Double = 1
    var isMuted = false

    /// Apps at 100% and unmuted are left alone: no tap, no added latency.
    var needsTap: Bool { isMuted || volume != 1 }
    var gain: Float { isMuted ? 0 : Float(volume) }
}

/// Persists per-app settings keyed by bundle ID. Only non-default settings are stored.
struct SettingsStore {
    private let defaults: UserDefaults
    private static let key = "appSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String: AppSetting] {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode([String: AppSetting].self, from: data) else {
            return [:]
        }
        return settings
    }

    func save(_ settings: [String: AppSetting]) {
        let stored = settings.filter { $0.value != AppSetting() }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
