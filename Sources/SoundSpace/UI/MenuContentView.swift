import SwiftUI

struct MenuContentView: View {
    let mixer: Mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sound Space").font(.headline)

            if mixer.apps.isEmpty {
                Text("No apps are playing audio")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(mixer.apps) { app in
                    AppRow(app: app, mixer: mixer)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit Sound Space") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 360)
        // Safety net in case a Core Audio notification was missed.
        .onAppear { mixer.refresh() }
    }
}

private struct AppRow: View {
    let app: AudioApp
    let mixer: Mixer

    var body: some View {
        let setting = mixer.setting(for: app.id)
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)

            Text(app.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 100, alignment: .leading)

            if let error = mixer.errors[app.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }

            Button {
                mixer.toggleMute(for: app.id)
            } label: {
                Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
                    .foregroundStyle(setting.isMuted ? .red : .primary)
            }
            .buttonStyle(.borderless)
            .help(setting.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { setting.volume * 100 },
                    set: { mixer.setVolume(($0 / 100).rounded(toPlaces: 2), for: app.id) }
                ),
                in: 0...100
            )
            .disabled(mixer.errors[app.id] != nil)

            Text("\(Int((setting.volume * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(setting.isMuted ? .secondary : .primary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
