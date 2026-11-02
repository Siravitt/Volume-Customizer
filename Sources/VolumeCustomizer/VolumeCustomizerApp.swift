import SwiftUI

@main
struct VolumeCustomizerApp: App {
    @State private var model: AppModel

    private static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        guard !Self.isUnitTestHost else { return }
        Task { @MainActor in model.launch() }
    }

    var body: some Scene {
        MenuBarExtra("Volume Customizer", systemImage: "slider.horizontal.3") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
