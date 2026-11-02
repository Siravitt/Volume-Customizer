import SwiftUI

struct MenuContentView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume Customizer").font(.headline)

            SystemVolumeRow(volume: model.systemVolume)

            Divider()

            if !model.permission.status.allowsCapture {
                PermissionBanner(model: model)
            }

            if model.mixer.apps.isEmpty {
                Text("No apps are playing audio")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(model.mixer.apps) { app in
                    AppRow(app: app, mixer: model.mixer)
                }
            }

            if let update = model.updates.available {
                Divider()
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                    Text("Volume Customizer \(update.version) is available")
                    Spacer()
                    Link("Download", destination: update.url)
                }
                .font(.callout)
            }

            Divider()

            Footer(loginItem: model.loginItem)
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { model.popoverOpened() }
    }
}

private struct SystemVolumeRow: View {
    let volume: SystemVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { volume.toggleMute() } label: {
                    Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        .frame(width: 20)
                        .foregroundStyle(volume.isMuted ? .red : .primary)
                }
                .buttonStyle(.borderless)
                .disabled(!volume.canMute)
                .help(volume.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(get: { volume.volume * 100 }, set: { volume.setVolume($0 / 100) }),
                    in: 0...100
                )
                .disabled(!volume.canSetVolume)

                Text(volume.canSetVolume ? "\(Int((volume.volume * 100).rounded()))%" : "–")
                    .monospacedDigit()
                    .foregroundStyle(volume.isMuted ? .secondary : .primary)
                    .frame(width: 40, alignment: .trailing)
            }
            Text(volume.canSetVolume ? volume.deviceName : "\(volume.deviceName) — volume is controlled by the device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct PermissionBanner: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume Customizer needs audio access to change app volumes.")
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.permission.status == .denied ? "Open System Settings" : "Set Up…") {
                    if model.permission.status == .denied {
                        model.permission.openSystemSettings()
                    } else {
                        model.showOnboarding()
                    }
                }
            }
        }
        .font(.callout)
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
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

private struct Footer: View {
    let loginItem: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { loginItem.isEnabled || loginItem.needsApproval }, set: { loginItem.setEnabled($0) })
                )
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit Volume Customizer") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text("Allow Volume Customizer in Login Items.")
                    Button("Open Settings") { loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                }
                .font(.caption)
            } else if let error = loginItem.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
