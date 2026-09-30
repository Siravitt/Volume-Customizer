import Foundation

/// A dotted numeric version such as `1.2.3`; a leading `v` and any `-suffix` are ignored.
struct AppVersion: Comparable {
    let components: [Int]

    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        if let dash = text.firstIndex(of: "-") { text = text[..<dash] }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
}

/// Checks GitHub Releases on launch and daily, and exposes a newer release if there is one.
/// Notify-only: the user downloads it (or runs `brew upgrade`) themselves.
@MainActor
@Observable
final class UpdateChecker {
    private(set) var available: AvailableUpdate?

    @ObservationIgnored private let repository: String?
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        let repository = bundle.object(forInfoDictionaryKey: "SoundSpaceGitHubRepository") as? String
        self.repository = repository?.isEmpty == false ? repository : nil
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        guard repository != nil, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    nonisolated static func update(from release: GitHubRelease, currentVersion: String) -> AvailableUpdate? {
        guard let latest = AppVersion(release.tagName),
              let current = AppVersion(currentVersion),
              current < latest else { return nil }
        return AvailableUpdate(version: release.tagName, url: release.htmlURL)
    }

    private func check() async {
        guard let repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            available = Self.update(from: release, currentVersion: currentVersion)
        } catch {
            log.debug("update check failed: \(String(describing: error), privacy: .public)")
        }
    }
}
