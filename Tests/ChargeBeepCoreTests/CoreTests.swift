import XCTest
@testable import ChargeBeepCore

final class AlarmTests: XCTestCase {
    func testThresholdUsesNormalizedCapacityWithoutRoundingDown() {
        for (current, maximum, expected) in [(60.0, 6000.0, true), (61, 6000, false), (0, 6000, true)] {
            var alarm = Alarm()
            let battery = Battery(current: current, maximum: maximum, onBattery: true)
            XCTAssertEqual(alarm.evaluate(battery: battery, settings: Settings(), activeUser: true, now: 0),
                           expected, "Capacity: \(current)/\(maximum)")
        }
    }

    func testRepeatedEventsDoNotPostponeOrDuplicateTheNextBeep() {
        var alarm = Alarm()
        let battery = Battery(current: 1, maximum: 100, onBattery: true)
        for (time, expected) in [(100.0, true), (100, false), (103, false), (109.9, false),
                                 (110, true), (110, false), (119.9, false), (120, true)] {
            XCTAssertEqual(alarm.evaluate(battery: battery, settings: Settings(), activeUser: true, now: time),
                           expected, "Time: \(time)")
        }
    }

    func testEveryStopConditionCancelsTheTimerAndRearmsImmediately() {
        let low = Battery(current: 0, maximum: 100, onBattery: true)
        let cases: [(String, Battery?, Settings, Bool)] = [
            ("AC", Battery(current: 0, maximum: 100, onBattery: false), Settings(), true),
            ("recovered", Battery(current: 2, maximum: 100, onBattery: true), Settings(), true),
            ("unknown", nil, Settings(), true),
            ("disabled", low, Settings(enabled: false), true),
            ("inactive user", low, Settings(), false)
        ]
        for (name, battery, settings, active) in cases {
            var alarm = Alarm()
            XCTAssertTrue(alarm.evaluate(battery: low, settings: Settings(), activeUser: true, now: 0), name)
            XCTAssertFalse(alarm.evaluate(battery: battery, settings: settings, activeUser: active, now: 1), name)
            XCTAssertNil(alarm.nextBeep, name)
            XCTAssertTrue(alarm.evaluate(battery: low, settings: Settings(), activeUser: true, now: 2), name)
        }
    }

    func testThresholdEditsApplyWithoutWaitingForAnotherBatteryChange() {
        var alarm = Alarm()
        let battery = Battery(current: 5, maximum: 100, onBattery: true)
        for (time, threshold, expected) in [(0.0, 1, false), (1, 5, true), (2, 6, false),
                                          (3, 4, false), (4, 5, true)] {
            XCTAssertEqual(alarm.evaluate(battery: battery, settings: Settings(threshold: threshold),
                                          activeUser: true, now: time), expected, "Threshold: \(threshold)")
        }
    }

    func testLateTimerDoesNotReplayMissedBeeps() {
        var alarm = Alarm()
        let battery = Battery(current: 1, maximum: 100, onBattery: true)
        for (time, expected) in [(0.0, true), (3600, true), (3600, false), (3609.9, false), (3610, true)] {
            XCTAssertEqual(alarm.evaluate(battery: battery, settings: Settings(), activeUser: true, now: time),
                           expected, "Time: \(time)")
        }
    }

    func testInvalidCapacityCannotTriggerAnAlarm() {
        for (current, maximum) in [(-1.0, 100.0), (1, 0), (0, -1), (101, 100),
                                   (.nan, 100), (1, .nan), (.infinity, 100), (1, .infinity)] {
            var alarm = Alarm()
            let battery = Battery(current: current, maximum: maximum, onBattery: true)
            XCTAssertNil(battery, "Capacity: \(current)/\(maximum)")
            XCTAssertFalse(alarm.evaluate(battery: battery, settings: Settings(threshold: 100),
                                          activeUser: true, now: 0))
            XCTAssertNil(alarm.nextBeep)
        }
    }
}

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ConfigStore(directory: directory)
        try store.prepare()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testNewStoreReadsPersistedSettingsAndPreservesUnchangedFields() throws {
        XCTAssertEqual(try store.load().threshold, 1)
        XCTAssertTrue(try store.load().enabled)
        try store.update { $0.threshold = 8 }
        let secondWriter = ConfigStore(directory: directory)
        try secondWriter.update { $0.enabled = false }
        XCTAssertEqual(try store.load().threshold, 8)
        XCTAssertFalse(try store.load().enabled)
    }

    func testRejectedUpdateLeavesExactBytesIntactAndReleasesTheLock() throws {
        try store.update { $0.threshold = 4 }
        let original = try Data(contentsOf: store.file)
        XCTAssertThrowsError(try store.update { $0.threshold = 101 })
        XCTAssertEqual(try Data(contentsOf: store.file), original)
        enum Interrupted: Error { case update }
        XCTAssertThrowsError(try store.update { $0.enabled = false; throw Interrupted.update })
        XCTAssertEqual(try Data(contentsOf: store.file), original)
        try store.update { $0.enabled = false }
        XCTAssertEqual(try store.load().threshold, 4)
        XCTAssertFalse(try store.load().enabled)
    }

    func testCorruptExistingFileIsNotTreatedAsMissingOrOverwritten() throws {
        for text in ["{broken", "{\"threshold\":0,\"enabled\":true}", "{\"threshold\":5}"] {
            let bytes = Data(text.utf8)
            try bytes.write(to: store.file)
            XCTAssertThrowsError(try store.load(), text)
            XCTAssertThrowsError(try store.update { $0.enabled = false }, text)
            XCTAssertEqual(try Data(contentsOf: store.file), bytes)
        }
    }
}
