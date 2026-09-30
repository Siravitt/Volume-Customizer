import Foundation
import Testing
@testable import SoundSpace

struct AppVersionTests {
    @Test(arguments: [
        ("0.1.0", "0.2.0"),
        ("0.9.9", "1.0.0"),
        ("1.2", "1.2.1"),
        ("v1.0.0", "v1.0.10"),
    ])
    func ordersVersions(older: String, newer: String) throws {
        #expect(try #require(AppVersion(older)) < #require(AppVersion(newer)))
    }

    @Test func treatsMissingComponentsAsZero() throws {
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("v1.0.0")))
    }

    @Test func ignoresPrereleaseSuffix() throws {
        #expect(try #require(AppVersion("1.2.0-beta.1")) == #require(AppVersion("1.2.0")))
    }

    @Test func rejectsGarbage() {
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }
}

struct UpdateCheckerTests {
    private let json = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/example/sound-space/releases/tag/v0.2.0", "name": "0.2.0"}"#

    @Test func reportsNewerRelease() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(UpdateChecker.update(from: release, currentVersion: "0.1.0") == AvailableUpdate(
            version: "v0.2.0",
            url: URL(string: "https://github.com/example/sound-space/releases/tag/v0.2.0")!
        ))
    }

    @Test func ignoresSameOrOlderRelease() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(UpdateChecker.update(from: release, currentVersion: "0.2.0") == nil)
        #expect(UpdateChecker.update(from: release, currentVersion: "0.3.0") == nil)
    }
}
