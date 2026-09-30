import SwiftUI

@main
struct SoundSpaceApp: App {
    @State private var model: AppModel

    private static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        guard !Self.isUnitTestHost else { return }
        Task { @MainActor in model.launch() }
    }

    var body: some Scene {
        MenuBarExtra("Sound Space", systemImage: "slider.horizontal.3") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
