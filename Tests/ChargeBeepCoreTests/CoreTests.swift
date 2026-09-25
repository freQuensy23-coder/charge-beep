import XCTest
@testable import ChargeBeepCore

final class CoreTests: XCTestCase {
    private func battery(_ n: Double = 1, ac: Bool = false) -> Battery? {
        Battery(current: n, maximum: 100, onBattery: !ac)
    }
    func testDefaultThresholdAndEnabled() { XCTAssertEqual(Settings(), Settings(threshold: 1, enabled: true)) }
    func testExactThresholdAndRepeatedNotificationDoesNotSpam() {
        var alarm = Alarm()
        XCTAssertFalse(alarm.evaluate(battery: battery(1.01), settings: Settings(), activeUser: true, now: 0))
        XCTAssertTrue(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 1))
        XCTAssertFalse(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 1.1))
        XCTAssertFalse(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 10.99))
        XCTAssertTrue(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 11))
    }
    func testACStopsAlarmEvenAtZeroAndUnplugRearms() {
        var alarm = Alarm()
        XCTAssertTrue(alarm.evaluate(battery: battery(0), settings: Settings(), activeUser: true, now: 0))
        XCTAssertFalse(alarm.evaluate(battery: battery(0, ac: true), settings: Settings(), activeUser: true, now: 1))
        XCTAssertNil(alarm.nextBeep)
        XCTAssertTrue(alarm.evaluate(battery: battery(0), settings: Settings(), activeUser: true, now: 2))
    }
    func testMissingAndInvalidBatteryNeverAlarm() {
        for invalid in [Battery(current: -1, maximum: 100, onBattery: true),
                        Battery(current: 1, maximum: 0, onBattery: true),
                        Battery(current: 101, maximum: 100, onBattery: true),
                        Battery(current: .nan, maximum: 100, onBattery: true),
                        Battery(current: 1, maximum: .infinity, onBattery: true)] {
            XCTAssertNil(invalid)
        }
        var alarm = Alarm()
        XCTAssertFalse(alarm.evaluate(battery: nil, settings: Settings(), activeUser: true, now: 0))
        XCTAssertNil(alarm.nextBeep)
    }
    func testBackgroundUserAndDisabledSettingsSilenceImmediately() {
        var alarm = Alarm()
        XCTAssertTrue(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 0))
        XCTAssertFalse(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: false, now: 1))
        XCTAssertNil(alarm.nextBeep)
        XCTAssertTrue(alarm.evaluate(battery: battery(), settings: Settings(), activeUser: true, now: 2))
        XCTAssertFalse(alarm.evaluate(battery: battery(), settings: Settings(enabled: false), activeUser: true, now: 3))
        XCTAssertNil(alarm.nextBeep)
    }
    func testThresholdChangeAndWakeDoNotCatchUpWithMultipleBeeps() {
        var alarm = Alarm()
        XCTAssertFalse(alarm.evaluate(battery: battery(5), settings: Settings(), activeUser: true, now: 0))
        XCTAssertTrue(alarm.evaluate(battery: battery(5), settings: Settings(threshold: 5), activeUser: true, now: 1))
        XCTAssertTrue(alarm.evaluate(battery: battery(5), settings: Settings(threshold: 5), activeUser: true, now: 1000))
        XCTAssertEqual(alarm.nextBeep, 1010)
        XCTAssertFalse(alarm.evaluate(battery: battery(5), settings: Settings(), activeUser: true, now: 1001))
        XCTAssertNil(alarm.nextBeep)
    }
    func testNormalizedCapacity() {
        let value = Battery(current: 30, maximum: 6000, onBattery: true)!
        XCTAssertEqual(value.percent, 0.5, accuracy: 0.00001)
        var alarm = Alarm()
        XCTAssertTrue(alarm.evaluate(battery: value, settings: Settings(), activeUser: true, now: 0))
    }
    func testParserStrictlyRejectsBadNumbersAndTrailingArguments() throws {
        XCTAssertEqual(try Command.parse(["set", "threshold", "100"]), .threshold(100))
        XCTAssertEqual(try Command.parse(["status", "--json"]), .status(json: true))
        XCTAssertEqual(try Command.parse(["set", "enabled", "false"]), .enabled(false))
        for value in ["0", "101", "-1", "1.5", "nan", "no", "9999999999999999999999999"] {
            XCTAssertThrowsError(try Command.parse(["set", "threshold", value]))
        }
        for args in [["status", "ignored"], ["set", "enabled", "yes"], ["update", "oops"]] {
            XCTAssertThrowsError(try Command.parse(args))
        }
    }
    func testAtomicSettingsRoundTripAndFailedWritePreservesOldValue() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        XCTAssertEqual(try store.load(), Settings())
        try store.update { $0.threshold = 5 }
        try store.update { $0.enabled = false }
        XCTAssertEqual(try store.load(), Settings(threshold: 5, enabled: false))
        XCTAssertThrowsError(try store.update { $0.threshold = 101 })
        XCTAssertEqual(try store.load(), Settings(threshold: 5, enabled: false))
        try Data("{\"threshold\":0,\"enabled\":true}".utf8).write(to: store.file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.update { $0.enabled = true })
        try Data("{invalid".utf8).write(to: store.file)
        XCTAssertThrowsError(try store.load())
    }
    func testIndependentUserStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = ConfigStore(directory: root.appendingPathComponent("alice"))
        let b = ConfigStore(directory: root.appendingPathComponent("bob"))
        try a.update { $0.threshold = 9 }
        XCTAssertEqual(try b.load().threshold, 1)
    }
    func testDuplicateAgentLockIsRejected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("lock")
        var first: FileLock? = try FileLock(url: url, nonBlocking: true)
        try withExtendedLifetime(first) { XCTAssertThrowsError(try FileLock(url: url, nonBlocking: true)) }
        first = nil
        XCTAssertNoThrow(try FileLock(url: url, nonBlocking: true))
    }
}
