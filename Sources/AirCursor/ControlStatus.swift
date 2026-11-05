import CoreMotion

/// One status shared by the menu bar and controls. Receiving motion is not the
/// same as controlling the pointer: paused gesture detection may still be live.
enum ControlStatus: Equatable {
    case accessibility, motionPermission, paused, reconnecting, audioHandoff
    case disconnected, waiting, pointer, scroll, dragging

    static func resolve(accessibility: Bool, motion: CMAuthorizationStatus,
                        tracking: Bool, streaming: Bool, reconnecting: Bool,
                        handoff: Bool, connected: Bool?, mode: TrackingMode,
                        dragging: Bool) -> Self {
        if !accessibility { return .accessibility }
        if motion != .authorized { return .motionPermission }
        if !tracking { return .paused }
        if reconnecting && !streaming { return .reconnecting }
        if streaming { return dragging ? .dragging : (mode == .scroll ? .scroll : .pointer) }
        if handoff { return .audioHandoff }
        if connected == false { return .disconnected }
        return .waiting
    }

    var label: String {
        switch self {
        case .accessibility, .motionPermission: "Permission"
        case .paused: "Paused"
        case .reconnecting: "Reconnecting"
        case .audioHandoff: "Audio route"
        case .disconnected: "Disconnected"
        case .waiting: "Waiting"
        case .pointer: "Pointer"
        case .scroll: "Scroll"
        case .dragging: "Dragging"
        }
    }

    var title: String {
        switch self {
        case .accessibility: "Allow pointer control"
        case .motionPermission: "Allow head motion"
        case .paused: "Control paused"
        case .reconnecting: "Reconnecting tracking"
        case .audioHandoff: "Select AirPods audio output"
        case .disconnected: "Headphones disconnected"
        case .waiting: "Waiting for head movement data"
        case .pointer: "Controlling the pointer"
        case .scroll: "Scrolling with your head"
        case .dragging: "Dragging with your head"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility, .motionPermission: "lock.shield"
        case .paused: "pause.circle"
        case .reconnecting: "arrow.clockwise"
        case .audioHandoff: "speaker.wave.2"
        case .disconnected, .waiting: "airpodspro"
        case .pointer: "cursorarrow.motionlines"
        case .scroll: "arrow.up.and.down.circle"
        case .dragging: "hand.draw"
        }
    }

    var isControlling: Bool { self == .pointer || self == .scroll || self == .dragging }
}
