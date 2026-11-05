import CoreMotion
import XCTest
@testable import AirCursor

final class ControlStatusTests: XCTestCase {
    private func resolve(accessibility: Bool = true, motion: CMAuthorizationStatus = .authorized,
                         tracking: Bool = true, streaming: Bool = true, reconnecting: Bool = false,
                         handoff: Bool = false, connected: Bool? = true,
                         mode: TrackingMode = .pointer, dragging: Bool = false) -> ControlStatus {
        .resolve(accessibility: accessibility, motion: motion, tracking: tracking,
                 streaming: streaming, reconnecting: reconnecting, handoff: handoff,
                 connected: connected, mode: mode, dragging: dragging)
    }

    func testPermissionBlockersOverrideLiveSamples() {
        XCTAssertEqual(resolve(accessibility: false), .accessibility)
        for permission in [CMAuthorizationStatus.denied, .restricted, .notDetermined] {
            XCTAssertEqual(resolve(motion: permission), .motionPermission)
        }
    }

    func testPausedGestureListenerIsNotReportedAsActiveControl() {
        XCTAssertEqual(resolve(tracking: false, streaming: true), .paused)
        XCTAssertEqual(resolve(tracking: false, streaming: false, connected: false), .paused)
    }

    func testScrollAndDragAreDistinctFromPointerControl() {
        XCTAssertEqual(resolve(), .pointer)
        XCTAssertEqual(resolve(mode: .scroll), .scroll)
        XCTAssertEqual(resolve(dragging: true), .dragging)
    }

    func testFreshMotionWinsOverStaleConnectionAndRecoveryFlags() {
        XCTAssertEqual(resolve(reconnecting: true, handoff: true, connected: false), .pointer)
    }

    func testSilentStreamExplainsRecoveryHandoffDisconnectionAndUnknownConnection() {
        XCTAssertEqual(resolve(streaming: false, reconnecting: true), .reconnecting)
        XCTAssertEqual(resolve(streaming: false, handoff: true), .audioHandoff)
        XCTAssertEqual(resolve(streaming: false, connected: false), .disconnected)
        XCTAssertEqual(resolve(streaming: false, connected: true), .waiting)
        XCTAssertEqual(resolve(streaming: false, connected: nil), .waiting)
    }
}
