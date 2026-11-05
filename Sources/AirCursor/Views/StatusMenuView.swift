import SwiftUI
import AirCursorCore

/// Native macOS status-item menu; detailed controls remain an explicit fallback.
struct StatusMenuView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("AirCursor — \(controller.controlStatus.title)")
        if controller.controlStatus == .paused, !controller.trackingChangeReason.isEmpty {
            Text("Paused by: \(controller.trackingChangeReason)")
        }
        Divider()
        Button(controller.trackingEnabled ? "Pause control" : "Resume control") {
            controller.toggleTracking()
        }
        .keyboardShortcut("t", modifiers: [.control, .option])
        Picker("Control mode", selection: Binding(get: { controller.mode }, set: { controller.setMode($0) })) {
            Text("Pointer").tag(TrackingMode.pointer)
            Text("Scroll").tag(TrackingMode.scroll)
        }
        .disabled(!controller.trackingEnabled)
        Toggle("Hover click", isOn: $controller.settings.dwell.enabled)
        Divider()
        if controller.controlStatus == .accessibility {
            Button("Allow pointer control…") { controller.requestAccessibility() }
        } else if controller.controlStatus == .motionPermission {
            Button("Allow head motion…") { controller.requestMotionAccess() }
        }
        Button(controller.recoveryInProgress ? "Reconnecting…" : "Reconnect tracking") {
            controller.reconnectTracking()
        }
        .disabled(controller.recoveryInProgress)
        if let device = controller.pairedHeadphones.first, controller.connectedHeadphones == nil {
            Button(controller.busyDeviceID == nil ? "Connect \(device.name)" : "Connecting…") {
                controller.connect(device)
            }
            .disabled(controller.busyDeviceID != nil)
        }
        Menu("Connection status") {
            Text(controller.connectedHeadphones?.name ?? (controller.motionStreaming ? "Headphones connected" : "No headphones detected"))
            Text(controller.motionStreaming ? "Motion data: live" : "Motion data: not arriving")
            Text("Mac audio: \(controller.diagnostics.soundOutput?.name ?? "Unknown")")
            if let last = controller.lastTriggerDescription { Text("Last action: \(last)") }
            Divider()
            Button("Sound settings…") { AppController.openSoundSettings() }
            Button("Copy diagnostics") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("Control status: \(controller.statusText)\nMode: \(controller.mode.title)\n" + controller.diagnostics.text, forType: .string)
            }
        }
        Divider()
        Button("Settings…") { openWindow(id: WindowID.main); NSApp.activate() }
        Button("Detailed controls…") { controller.showControls() }
            .keyboardShortcut("m", modifiers: [.control, .option])
        Button("Quit AirCursor") { NSApp.terminate(nil) }
    }
}
