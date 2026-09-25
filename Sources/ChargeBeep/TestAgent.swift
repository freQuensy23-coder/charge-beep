#if DEBUG
import Foundation
import ChargeBeepCore

/// Debug-only process harness. Production binaries cannot spoof battery state.
/// JSON lines enter the SAME Alarm state machine used by Agent, without draining hardware.
private struct Event: Decodable {
    var current: Double?
    var maximum: Double?
    var onBattery: Bool
    var active: Bool
    var now: Double
}
func runTestAgent(_ arguments: [String]) throws {
    guard arguments.isEmpty else { throw BeepError.message("_test-agent takes JSON lines on stdin.") }
    let store = ConfigStore()
    var alarm = Alarm()
    while let line = readLine() {
        let event = try JSONDecoder().decode(Event.self, from: Data(line.utf8))
        let battery = event.current.flatMap { current in
            event.maximum.flatMap { Battery(current: current, maximum: $0, onBattery: event.onBattery) }
        }
        let beep = alarm.evaluate(battery: battery, settings: try store.load(), activeUser: event.active, now: event.now)
        let result: [String: Any] = ["beep": beep, "next": alarm.nextBeep.map { $0 as Any } ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: result)
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
#endif
