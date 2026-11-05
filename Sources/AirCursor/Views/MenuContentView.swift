import SwiftUI
import AirCursorCore

struct MenuContentView: View {
    var isControlWindow = false
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var status: ControlStatus { controller.controlStatus }
    private var colors: ControlColors { ControlColors(dark: colorScheme == .dark) }
    private var statusColor: Color {
        status.isControlling ? colors.live : (status == .paused ? colors.secondary : colors.warning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title).font(.system(size: 16, weight: .semibold))
                    Text(statusDetail).font(.system(size: 12)).foregroundStyle(colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack {
                Button(controller.trackingEnabled ? "Pause control" : "Resume control") {
                    controller.toggleTracking()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.accessibilityTrusted || controller.motionAuthorization != .authorized)
                Spacer()
                Text(HotKey.toggleTracking.display).font(.system(size: 12)).foregroundStyle(colors.secondary)
            }

            permissionAction

            Picker("Control mode", selection: Binding(get: { controller.mode }, set: { controller.setMode($0) })) {
                Text("Pointer").tag(TrackingMode.pointer)
                Text("Scroll").tag(TrackingMode.scroll)
            }
            .pickerStyle(.segmented)
            .disabled(!controller.trackingEnabled)

            separator

            VStack(spacing: 8) {
                statusRow("Headphones", value: headphoneText)
                statusRow("Motion data", value: controller.motionStreaming ? "Live" : "Not arriving")
                statusRow("Mac audio", value: controller.diagnostics.soundOutput?.name ?? "Unknown")
            }
            HStack {
                Button(controller.recoveryInProgress ? "Reconnecting…" : "Reconnect tracking") {
                    controller.reconnectTracking()
                }
                .disabled(controller.recoveryInProgress)
                if status == .audioHandoff {
                    Button("Sound settings…") { AppController.openSoundSettings() }
                } else if controller.connectedHeadphones == nil, let device = controller.pairedHeadphones.first {
                    Button(controller.busyDeviceID == nil ? "Connect headphones" : "Connecting…") {
                        controller.connect(device)
                    }
                    .disabled(controller.busyDeviceID != nil)
                }
            }

            if let error = controller.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            separator

            HStack {
                Text("Pointer speed")
                Spacer()
                Text(String(format: "%.1f×", controller.settings.pointer.sensitivity))
                    .monospacedDigit().foregroundStyle(colors.secondary)
            }
            Slider(value: $controller.settings.pointer.sensitivity, in: 0.2...4)
                .accessibilityLabel("Pointer speed")
            Toggle("Hover click", isOn: $controller.settings.dwell.enabled)
            if let last = controller.lastTriggerDescription {
                Text("Last action: \(last)").font(.system(size: 12)).foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            separator

            HStack {
                Button("Settings…") { openWindow(id: WindowID.main); NSApp.activate() }
                Button(copied ? "Copied" : "Copy diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Control status: \(status.title)\nMode: \(controller.mode.title)\n" + controller.diagnostics.text, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            HStack {
                if !isControlWindow {
                    Button("Open controls") { controller.showControls() }
                }
                Button("Guided tour") { openWindow(id: WindowID.tour); NSApp.activate() }
                Spacer()
                Text(HotKey.controls.display).font(.system(size: 12)).foregroundStyle(colors.secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(colors.text)
        .tint(colors.accent)
        .padding(16)
        .frame(width: 360)
        .background(colors.background)
        .task { controller.refreshDevices() }
    }

    private var separator: some View { Rectangle().fill(colors.border).frame(height: 0.5) }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(colors.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .font(.system(size: 12))
    }

    private var headphoneText: String {
        if let device = controller.connectedHeadphones { return device.name }
        if controller.motionStreaming { return "Connected" }
        if controller.headphoneConnected == false { return "Disconnected" }
        return "Not detected"
    }

    private var statusDetail: String {
        switch status {
        case .paused:
            return controller.trackingChangeReason.isEmpty ? "Resume when you are ready." : "Paused by: \(controller.trackingChangeReason)"
        case .pointer: return "Turn your head to move the pointer."
        case .scroll: return "Head movement scrolls; the pointer stays still."
        case .dragging: return "Press \(HotKey.drag.display) to release the drag."
        case .accessibility: return "Enable AirCursor in System Settings."
        case .motionPermission: return "Motion permission is \(controller.motionAuthorization.label)."
        case .audioHandoff: return "Choose your AirPods as this Mac’s sound output."
        case .disconnected: return "Connect your headphones to this Mac."
        case .waiting: return "Control is on, but no fresh sensor data is arriving."
        case .reconnecting: return "Restarting the headphone motion connection."
        }
    }

    @ViewBuilder private var permissionAction: some View {
        if status == .accessibility {
            Button("Allow pointer control…") { controller.requestAccessibility() }
        } else if status == .motionPermission {
            if controller.motionAuthorization == .notDetermined {
                Button("Allow motion…") { controller.requestMotionAccess() }
            } else {
                Button("Motion settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

/// Radix Colors: Slate 2/6/11/12, Blue 9, Green 11 and Amber 11.
/// https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale
private struct ControlColors {
    let dark: Bool
    var background: Color { color(0xf9f9fb, 0x18191b) }
    var border: Color { color(0xd9d9e0, 0x363a3f) }
    var secondary: Color { color(0x60646c, 0xb0b4ba) }
    var text: Color { color(0x1c2024, 0xedeef0) }
    var accent: Color { color(0x0090ff, 0x0090ff) }
    var live: Color { color(0x218358, 0x3dd68c) }
    var warning: Color { color(0xab6400, 0xffca16) }
    private func color(_ light: UInt32, _ night: UInt32) -> Color {
        let value = dark ? night : light
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
