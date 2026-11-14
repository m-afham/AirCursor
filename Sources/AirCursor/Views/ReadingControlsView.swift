import SwiftUI
import AirCursorCore

/// Playback is started over the document with a shortcut or stem press, avoiding
/// synthetic scroll events being sent to this menu/settings window.
struct ReadingControlsView: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.statusText).font(.callout.weight(.medium))
            HStack {
                Button("Slower") { controller.adjustReadingSpeed(-5) }
                Text("\(Int(controller.settings.reading.boundedSpeed)) points/s")
                    .monospacedDigit()
                Button("Faster") { controller.adjustReadingSpeed(5) }
            }
            HStack {
                Button("Pause") { controller.pauseReading() }
                    .disabled(controller.readingState != .running)
                Button("Exit reading") { controller.setMode(.pointer) }
            }
            Text("Close this panel and point at your document. ⌃⌥P starts or pauses; ⌃⌥N steps forward; ⌃⌥B goes back. Steps leave reading paused.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Stem: once to start/pause, twice to go back, three times to exit. Tilt left/right for speed. Shake to pause; shake again while paused to exit. Nods and clicks are ignored.")
                .font(.caption).foregroundStyle(.secondary)
            if !controller.settings.stemControlsEnabled {
                Text("Stem controls are off. Use the keyboard shortcuts or enable stem controls in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
