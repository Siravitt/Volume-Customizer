import Foundation
import Testing
@testable import SoundSpace

struct SettingsStoreTests {
    private func makeStore() -> SettingsStore {
        let suite = "SoundSpaceTests.\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func roundTripsSettings() {
        let store = makeStore()
        store.save([
            "com.spotify.client": AppSetting(volume: 0.4, isMuted: false),
            "com.hnc.Discord": AppSetting(volume: 1, isMuted: true),
        ])

        #expect(store.load() == [
            "com.spotify.client": AppSetting(volume: 0.4, isMuted: false),
            "com.hnc.Discord": AppSetting(volume: 1, isMuted: true),
        ])
    }

    @Test func dropsDefaultSettings() {
        let store = makeStore()
        store.save(["com.apple.Music": AppSetting()])

        #expect(store.load().isEmpty)
    }

    @Test func loadsEmptyWhenNothingSaved() {
        #expect(makeStore().load().isEmpty)
    }
}

struct AppSettingTests {
    @Test func onlyNonDefaultSettingsNeedATap() {
        #expect(!AppSetting().needsTap)
        #expect(AppSetting(volume: 0.99).needsTap)
        #expect(AppSetting(isMuted: true).needsTap)
    }

    @Test func mutedGainIsZero() {
        #expect(AppSetting(volume: 0.7, isMuted: true).gain == 0)
        #expect(AppSetting(volume: 0.5).gain == 0.5)
    }
}

struct AppListPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func showsPlayingApps() {
        #expect(AppListPolicy.isVisible(isPlaying: true, hasCustomSetting: false, stoppedAt: nil, now: now))
    }

    @Test func showsAppsWithCustomSettingsEvenWhenSilent() {
        #expect(AppListPolicy.isVisible(isPlaying: false, hasCustomSetting: true, stoppedAt: nil, now: now))
    }

    @Test func lingersForThirtySecondsAfterStopping() {
        #expect(AppListPolicy.isVisible(isPlaying: false, hasCustomSetting: false, stoppedAt: now - 29, now: now))
        #expect(!AppListPolicy.isVisible(isPlaying: false, hasCustomSetting: false, stoppedAt: now - 30, now: now))
    }

    @Test func hidesSilentAppsThatNeverPlayed() {
        #expect(!AppListPolicy.isVisible(isPlaying: false, hasCustomSetting: false, stoppedAt: nil, now: now))
    }
}
