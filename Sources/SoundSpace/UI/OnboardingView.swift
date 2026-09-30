import SwiftUI

struct OnboardingView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Text("Welcome to Sound Space")
                    .font(.title2.bold())
            }

            Text("Sound Space sets the volume of each app by passing its audio through Sound Space before it reaches your speakers.")

            Text("macOS calls this **system audio recording**, so it asks for your permission. Audio is processed on your Mac in real time. Nothing is recorded, saved, or sent anywhere, and the source code is public so anyone can check.")
                .foregroundStyle(.secondary)

            statusSection
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.permission.status {
        case .notDetermined:
            HStack {
                Spacer()
                Button("Continue") {
                    Task { await model.requestPermission() }
                }
                .keyboardShortcut(.defaultAction)
            }

        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Access is turned off", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text("Open System Settings → Privacy & Security → Screen & System Audio Recording, and turn on Sound Space under **System Audio Recording Only**.")
                HStack {
                    Spacer()
                    Button("Check Again") { model.refreshPermission() }
                    Button("Open System Settings") { model.permission.openSystemSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .authorized, .unknown:
            VStack(alignment: .leading, spacing: 8) {
                Label("You're all set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("Sound Space lives in your menu bar. Click its icon to change the volume of any app that's playing.")
                HStack {
                    Spacer()
                    Button("Done") { model.closeOnboarding() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
