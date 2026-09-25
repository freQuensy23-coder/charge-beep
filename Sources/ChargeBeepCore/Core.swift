import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Settings: Codable, Equatable {
    public var threshold: Int
    public var enabled: Bool
    public init(threshold: Int = 1, enabled: Bool = true) {
        self.threshold = threshold
        self.enabled = enabled
    }
    public func validate() throws {
        guard (1...100).contains(threshold) else {
            throw BeepError.message("Threshold must be an integer from 1 to 100.")
        }
    }
}

public enum BeepError: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
        switch self { case .message(let text): return text }
    }
}

/// Nil is unknown/no internal battery, never implicitly zero percent.
public struct Battery: Codable, Equatable {
    public let percent: Double
    public let onBattery: Bool
    public init?(current: Double, maximum: Double, onBattery: Bool) {
        guard current.isFinite, maximum.isFinite, maximum > 0,
              current >= 0, current <= maximum else { return nil }
        self.percent = (current / maximum) * 100
        self.onBattery = onBattery
    }
}

/// The production daemon and the process E2E harness use this same state machine.
/// Deadlines are monotonic uptime, not wall-clock dates.
public struct Alarm {
    public static let interval: TimeInterval = 10
    public private(set) var nextBeep: TimeInterval?
    public init() {}
    public mutating func evaluate(battery: Battery?, settings: Settings,
                                  activeUser: Bool, now: TimeInterval) -> Bool {
        guard settings.enabled, activeUser, let battery, battery.onBattery,
              battery.percent <= Double(settings.threshold) else {
            nextBeep = nil
            return false
        }
        if let nextBeep, now < nextBeep { return false }
        nextBeep = now + Self.interval
        return true
    }
}

/// A persistent lock inode prevents concurrent UI/CLI writers losing updates.
/// Never unlink this lock: that would let two processes lock different inodes.
public final class FileLock {
    private var fd: Int32 = -1
    public init(url: URL, nonBlocking: Bool = false) throws {
        fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw BeepError.message("Cannot open lock: \(url.path)") }
        guard flock(fd, LOCK_EX | (nonBlocking ? LOCK_NB : 0)) == 0 else {
            close(fd); fd = -1
            throw BeepError.message("Another Charge Beep process holds this lock.")
        }
    }
    deinit { if fd >= 0 { _ = flock(fd, LOCK_UN); close(fd) } }
}

public struct ConfigStore {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("settings.json") }
    public init(directory: URL? = nil) {
        // Also provides an isolated directory for tests; no system files are modified.
        let override = ProcessInfo.processInfo.environment["CHARGE_BEEP_HOME"]
        self.directory = directory ?? override.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ChargeBeep", isDirectory: true)
    }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
    public func load() throws -> Settings {
        do {
            let data = try Data(contentsOf: file)
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            try settings.validate()
            return settings
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Settings()
        }
    }
    @discardableResult
    public func update(_ change: (inout Settings) throws -> Void) throws -> Settings {
        try prepare()
        let lock = try FileLock(url: directory.appendingPathComponent("settings.lock"))
        return try withExtendedLifetime(lock) {
            var settings = try load()
            try change(&settings)
            try settings.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: file, options: .atomic)
            return settings
        }
    }
}

public enum Command: Equatable {
    case status(json: Bool), threshold(Int), enabled(Bool), ui, testSound, update, agent, help, version
    public static func parse(_ args: [String]) throws -> Command {
        if args.count == 3 && args[0] == "set" && args[1] == "threshold" {
            guard let value = Int(args[2]), (1...100).contains(value) else {
                throw BeepError.message("Threshold must be an integer from 1 to 100.")
            }
            return .threshold(value)
        }
        switch args {
        case [], ["help"], ["--help"], ["-h"]: return .help
        case ["version"], ["--version"]: return .version
        case ["status"]: return .status(json: false)
        case ["status", "--json"]: return .status(json: true)
        case ["ui"]: return .ui
        case ["test"]: return .testSound
        case ["update"]: return .update
        case ["agent"]: return .agent
        case ["set", "enabled", "true"]: return .enabled(true)
        case ["set", "enabled", "false"]: return .enabled(false)
        default: throw BeepError.message("Unknown arguments. Run charge-beep help.")
        }
    }
}

public struct ProcessResult {
    public let code: Int32
    public let output: String
}

public func runProcess(_ executable: String, _ arguments: [String], capture: Bool = true) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    if capture { process.standardOutput = pipe; process.standardError = pipe }
    try process.run()
    // Drain before waiting so a full pipe cannot deadlock the child.
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    return ProcessResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

public func logError(_ error: Error) {
    FileHandle.standardError.write(Data("charge-beep: \(error)\n".utf8))
}
