import Foundation

/// Preferences only: a running session must never survive an app restart.
public struct ReadingSettings: Codable, Equatable, Sendable {
    public var pointsPerSecond: Double = 30
    public var stepPoints: Double = 300

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReadingSettings()
        pointsPerSecond = c.value(.pointsPerSecond, default: d.pointsPerSecond)
        stepPoints = c.value(.stepPoints, default: d.stepPoints)
    }

    public var boundedSpeed: Double {
        pointsPerSecond.isFinite ? min(max(pointsPerSecond, 5), 150) : 30
    }

    public var boundedStep: Double {
        stepPoints.isFinite ? min(max(stepPoints, 40), 800) : 300
    }
}

/// Deterministic reading state. Positive output reveals content below.
/// The app adapter must check permissions, target and real input before every tick
/// and before start/step commands. It must convert output to CGEvent scroll signs.
public struct ReadingSession: Sendable {
    public enum State: Equatable, Sendable { case inactive, ready, running, paused }
    public private(set) var state: State = .inactive
    private var remainder: Double = 0

    public init() {}

    public mutating func enter() {
        state = .ready
        remainder = 0
    }

    public mutating func start() {
        guard state == .ready || state == .paused else { return }
        state = .running
    }

    public mutating func pause() {
        guard state != .inactive else { return }
        state = .paused
        remainder = 0
    }

    public mutating func exit() {
        state = .inactive
        remainder = 0
    }

    /// An interruption latches paused; fresh input never resumes automatically.
    /// Long frame gaps are interruptions, not distance to catch up later.
    public mutating func tick(dt: Double, permitted: Bool, settings: ReadingSettings) -> Int32 {
        guard state == .running else { return 0 }
        guard permitted, dt.isFinite, dt > 0, dt <= 0.1 else {
            pause()
            return 0
        }
        remainder += settings.boundedSpeed * dt
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        return Int32(whole)
    }

    /// Explicit forward/back movement always leaves continuous scrolling paused.
    public mutating func step(backward: Bool, permitted: Bool, settings: ReadingSettings) -> Int32 {
        guard state != .inactive else { return 0 }
        pause()
        guard permitted else { return 0 }
        return Int32(settings.boundedStep) * (backward ? -1 : 1)
    }
}
