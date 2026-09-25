import Foundation
import ChargeBeepCore
#if os(macOS)
import Darwin
#else
import Glibc
#endif

let help = """
Charge Beep \(BuildInfo.version)
  charge-beep status [--json]
  charge-beep set threshold N       1...100; default 1
  charge-beep set enabled true|false
  charge-beep ui                    open settings; closing them does not stop monitoring
  charge-beep test                  play the alarm once
  charge-beep update                update through Homebrew (may ask for admin password)
  charge-beep version
Settings apply to the current user. The installer enables background startup for all users.
"""

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = try Command.parse(args)
    let store = ConfigStore()
    switch command {
    case .help: print(help)
    case .version: print(BuildInfo.version)
    case .threshold(let n): try store.update { $0.threshold = n }; print("threshold=\(n)")
    case .enabled(let enabled): try store.update { $0.enabled = enabled }; print("enabled=\(enabled)")
    case .status(let json):
        let settings = try store.load()
        var result: [String: Any] = ["version": BuildInfo.version, "threshold": settings.threshold,
            "enabled": settings.enabled, "settings_path": store.file.path,
            "repeat_seconds": Alarm.interval]
        #if os(macOS)
        let battery = Mac.battery()
        let service = Mac.agentStatus()
        result["battery_percent"] = battery.map { $0.percent as Any } ?? NSNull()
        result["on_battery"] = battery.map { $0.onBattery as Any } ?? NSNull()
        result["active_user"] = Mac.isActiveUser()
        result["agent_running"] = service.running
        result["agent_pid"] = service.pid.map { $0 as Any } ?? NSNull()
        result["autostart_installed"] = FileManager.default.fileExists(
            atPath: "/Library/LaunchAgents/\(BuildInfo.label).plist")
        #else
        result["agent_running"] = false
        result["battery_percent"] = NSNull()
        #endif
        if json {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            for key in result.keys.sorted() { print("\(key): \(result[key]!)") }
        }
    case .ui:
        #if os(macOS)
        try Mac.openUI()
        #else
        throw BeepError.message("macOS is required.")
        #endif
    case .agent:
        #if os(macOS)
        guard getuid() != 0 else { throw BeepError.message("Run as a user LaunchAgent, not as root.") }
        let agent = Agent()
        try agent.start()
        withExtendedLifetime(agent) { RunLoop.main.run() }
        #else
        throw BeepError.message("macOS is required.")
        #endif
    case .testSound:
        #if os(macOS)
        let beeper = try Beeper()
        beeper.play()
        withExtendedLifetime(beeper) { RunLoop.main.run(until: Date(timeIntervalSinceNow: 1)) }
        #else
        throw BeepError.message("macOS is required.")
        #endif
    case .update:
        #if os(macOS)
        guard getuid() != 0 else { throw BeepError.message("Run update without sudo; Homebrew requests privileges for the installer.") }
        // Only known Homebrew locations; never execute an arbitrary PATH match as an updater.
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw BeepError.message("Install Homebrew and tap freQuensy23-coder/charge-beep first (see README).") }
        for arguments in [["update"], ["upgrade", "--cask", BuildInfo.tap]] {
            let result = try runProcess(brew, arguments, capture: false)
            guard result.code == 0 else { throw BeepError.message("Homebrew exited with status \(result.code).") }
        }
        #else
        throw BeepError.message("macOS is required.")
        #endif
    }
}

do { try main() } catch { logError(error); exit(1) }
