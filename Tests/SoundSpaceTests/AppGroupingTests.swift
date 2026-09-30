import Testing
@testable import SoundSpace

struct AppGroupingTests {
    @Test(arguments: [
        ("/Applications/Spotify.app/Contents/MacOS/Spotify", "/Applications/Spotify.app"),
        (
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
            "/Applications/Google Chrome.app"
        ),
        (
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        ),
    ])
    func findsOutermostAppBundle(path: String, expected: String) {
        #expect(AppGrouping.outermostAppBundle(in: path) == expected)
    }

    @Test func ignoresPathsOutsideAppBundles() {
        #expect(AppGrouping.outermostAppBundle(in: "/usr/libexec/coreaudiod") == nil)
        #expect(AppGrouping.outermostAppBundle(
            in: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        ) == nil)
    }

    @Test func groupsProcessesByBundleAndDropsDaemons() {
        let groups = AppGrouping.group([
            ProcessSnapshot(objectID: 12, isPlaying: false, appBundlePath: "/Applications/Chrome.app"),
            ProcessSnapshot(objectID: 5, isPlaying: true, appBundlePath: "/Applications/Chrome.app"),
            ProcessSnapshot(objectID: 7, isPlaying: false, appBundlePath: nil),
            ProcessSnapshot(objectID: 3, isPlaying: false, appBundlePath: "/Applications/Music.app"),
        ])

        #expect(groups == [
            AppGroup(bundlePath: "/Applications/Chrome.app", processObjectIDs: [5, 12], isPlaying: true),
            AppGroup(bundlePath: "/Applications/Music.app", processObjectIDs: [3], isPlaying: false),
        ])
    }
}
