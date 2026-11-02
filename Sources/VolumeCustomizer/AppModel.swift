import AppKit
import SwiftUI

/// Wires the app's parts together and owns app-level flows (launch, onboarding).
@MainActor
@Observable
final class AppModel {
    let mixer = Mixer()
    let systemVolume = SystemVolume()
    let permission = CapturePermission()
    let loginItem = LoginItem()
    let updates = UpdateChecker()

    @ObservationIgnored private var onboardingWindow: NSWindow?

    func launch() {
        permission.refresh()
        loginItem.refresh()
        mixer.captureAllowed = permission.status.allowsCapture
        mixer.start()
        systemVolume.start()
        updates.start()
        if permission.status != .authorized && permission.status != .unknown {
            showOnboarding()
        }
    }

    /// Re-checks things the user may have changed in System Settings while we were closed.
    func popoverOpened() {
        refreshPermission()
        loginItem.refresh()
        mixer.refresh()
    }

    func refreshPermission() {
        permission.refresh()
        mixer.captureAllowed = permission.status.allowsCapture
    }

    func requestPermission() async {
        await permission.request()
        mixer.captureAllowed = permission.status.allowsCapture
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: self)))
            window.title = "Welcome to Volume Customizer"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }
}
