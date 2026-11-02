import CoreAudio

/// One Core Audio process object, resolved to the app bundle that owns it.
struct ProcessSnapshot: Equatable {
    let objectID: AudioObjectID
    let isPlaying: Bool
    /// Outermost `.app` bundle of the process responsible for this one, if any.
    let appBundlePath: String?
}

/// All audio processes belonging to one app bundle.
struct AppGroup: Equatable {
    let bundlePath: String
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool
}

enum AppGrouping {
    /// `/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/Helper`
    /// → `/Applications/Google Chrome.app`
    static func outermostAppBundle(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }

    /// Groups processes by app bundle, dropping processes that don't belong to an app
    /// (system daemons). Result is sorted by bundle path for stable ordering.
    static func group(_ processes: [ProcessSnapshot]) -> [AppGroup] {
        var groups: [String: AppGroup] = [:]
        for process in processes {
            guard let path = process.appBundlePath else { continue }
            groups[path, default: AppGroup(bundlePath: path, processObjectIDs: [], isPlaying: false)]
                .processObjectIDs.append(process.objectID)
            if process.isPlaying { groups[path]?.isPlaying = true }
        }
        return groups.values
            .map { group in
                var group = group
                group.processObjectIDs.sort()
                return group
            }
            .sorted { $0.bundlePath < $1.bundlePath }
    }
}
