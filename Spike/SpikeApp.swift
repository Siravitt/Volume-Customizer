import SwiftUI

@main
struct SpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup("Sound Space Spike") {
            ContentView(model: model)
                .frame(minWidth: 520, minHeight: 480)
        }
    }
}

@MainActor
@Observable
final class SpikeModel {
    var processes: [AudioProcess] = []
    var selection: AudioProcess.ID?
    var gainPercent: Double = 30 {
        didSet { player.targetGain = Float(gainPercent / 100) }
    }
    var status = "Idle"
    var diagnostics: [String] = []
    var isRunning = false

    private let player = ProcessTapPlayer()

    func refresh() {
        do {
            processes = try AudioProcess.all().sorted {
                ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased())
            }
        } catch {
            status = "\(error)"
        }
    }

    func start() {
        guard let process = processes.first(where: { $0.id == selection }) else { return }
        player.targetGain = Float(gainPercent / 100)
        do {
            diagnostics = try player.start(process: process)
            status = "Tapping \(process.name)"
            isRunning = true
        } catch {
            diagnostics = []
            status = "\(error)"
            isRunning = false
        }
    }

    func stop() {
        player.stop()
        isRunning = false
        status = "Idle"
    }
}

struct ContentView: View {
    @Bindable var model: SpikeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps with audio clients").font(.headline)
                Spacer()
                Button("Refresh", action: model.refresh)
            }

            List(model.processes, selection: $model.selection) { process in
                HStack {
                    Image(systemName: process.isPlaying ? "speaker.wave.2.fill" : "speaker")
                        .foregroundStyle(process.isPlaying ? .green : .secondary)
                        .frame(width: 20)
                    Text(process.name)
                    Spacer()
                    Text(process.bundleID).foregroundStyle(.secondary).font(.caption)
                }
            }
            .disabled(model.isRunning)

            HStack {
                Text("Gain")
                Slider(value: $model.gainPercent, in: 0...200, step: 1)
                Text("\(Int(model.gainPercent))%").monospacedDigit().frame(width: 48, alignment: .trailing)
            }

            HStack {
                Button("Start tap", action: model.start)
                    .disabled(model.isRunning || model.selection == nil)
                Button("Stop", action: model.stop)
                    .disabled(!model.isRunning)
                Spacer()
            }

            Text(model.status).font(.callout)
            ForEach(model.diagnostics, id: \.self) { line in
                Text(line).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
        .onAppear(perform: model.refresh)
    }
}
