import XCTest
@testable import AirCursorCore

final class ReadingTests: XCTestCase {
    func testPauseDiscardsFractionalMovement() {
        var session = ReadingSession()
        session.enter()
        session.start()
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
        session.pause()
        session.start()
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 1)
    }

    func testReenterAlwaysRequiresStart() {
        var session = ReadingSession()
        session.enter()
        session.start()
        session.enter()
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
    }

    func testExplicitStartAndExit() {
        var session = ReadingSession()
        session.start()
        XCTAssertEqual(session.state, .inactive)
        session.enter()
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
        XCTAssertEqual(session.state, .ready)
        session.start()
        XCTAssertEqual(session.state, .running)
        session.exit()
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
    }

    func testFractionalMotionIsFrameRateIndependent() {
        for fps in [30, 60, 120] {
            var session = ReadingSession()
            session.enter()
            session.start()
            let total = (0..<fps * 10).reduce(Int32(0)) { sum, _ in
                sum + session.tick(dt: 1 / Double(fps), permitted: true, settings: .init())
            }
            XCTAssertEqual(Double(total), 300, accuracy: 1)
        }
    }

    func testInterruptionRequiresExplicitResume() {
        var session = ReadingSession()
        session.enter()
        session.start()
        XCTAssertEqual(session.tick(dt: 0.02, permitted: false, settings: .init()), 0)
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(session.tick(dt: 0.02, permitted: true, settings: .init()), 0)
        session.start()
        XCTAssertEqual(session.state, .running)
    }

    func testBadFrameIntervalsPauseWithoutCatchUp() {
        for dt in [Double.nan, .infinity, -1, 0, 1] {
            var session = ReadingSession()
            session.enter()
            session.start()
            XCTAssertEqual(session.tick(dt: dt, permitted: true, settings: .init()), 0)
            XCTAssertEqual(session.state, .paused)
        }
    }

    func testStepsPauseAndRespectPermission() {
        var session = ReadingSession()
        XCTAssertEqual(session.step(backward: false, permitted: true, settings: .init()), 0)
        session.enter()
        session.start()
        XCTAssertEqual(session.step(backward: true, permitted: true, settings: .init()), -300)
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(session.step(backward: false, permitted: false, settings: .init()), 0)
        XCTAssertEqual(session.step(backward: false, permitted: true, settings: .init()), 300)
    }

    func testOldAndMalformedSettingsRemainReadable() throws {
        for json in ["{}", "{\"reading\":null}", "{\"reading\":\"bad\"}",
                     "{\"reading\":{\"pointsPerSecond\":\"bad\"}}"] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.reading, ReadingSettings())
        }
        var settings = AppSettings()
        settings.reading.pointsPerSecond = 45
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.reading, settings.reading)
    }

    func testUntrustedNumericSettingsAreBounded() {
        var settings = ReadingSettings()
        settings.pointsPerSecond = .nan
        settings.stepPoints = .infinity
        XCTAssertEqual(settings.boundedSpeed, 30)
        XCTAssertEqual(settings.boundedStep, 300)
        settings.pointsPerSecond = -100
        settings.stepPoints = 1e100
        XCTAssertEqual(settings.boundedSpeed, 5)
        XCTAssertEqual(settings.boundedStep, 800)
    }
}
