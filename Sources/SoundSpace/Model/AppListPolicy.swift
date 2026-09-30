import Foundation

/// Decides which running apps get a row in the popover.
enum AppListPolicy {
    /// How long a row stays after its app stops playing, so pausing doesn't make it vanish.
    static let linger: TimeInterval = 30

    static func isVisible(isPlaying: Bool, hasCustomSetting: Bool, stoppedAt: Date?, now: Date) -> Bool {
        if isPlaying || hasCustomSetting { return true }
        guard let stoppedAt else { return false }
        return now.timeIntervalSince(stoppedAt) < linger
    }
}
