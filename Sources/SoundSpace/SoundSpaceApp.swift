import SwiftUI

@main
struct SoundSpaceApp: App {
    @State private var mixer = Mixer()

    var body: some Scene {
        MenuBarExtra("Sound Space", systemImage: "slider.horizontal.3") {
            MenuContentView(mixer: mixer)
        }
        .menuBarExtraStyle(.window)
    }
}
