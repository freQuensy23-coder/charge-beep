#if os(macOS)
import Foundation
import IOKit.ps
import SystemConfiguration
import AudioToolbox
import Darwin

public enum Mac {
    public static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                  let data = raw as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  (data[kIOPSIsPresentKey] as? Bool) != false,
                  let current = data[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = data[kIOPSMaxCapacityKey] as? NSNumber,
                  let state = data[kIOPSPowerSourceStateKey] as? String else { continue }
            // On AC but "not charging" is still AC; do not alarm indefinitely.
            guard state == kIOPSBatteryPowerValue || state == kIOPSACPowerValue else { return nil }
            return Battery(current: current.doubleValue, maximum: maximum.doubleValue,
                           onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
    public static func isActiveUser() -> Bool {
        var uid: uid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?,
              name != "loginwindow", uid != 0 else { return false }
        return uid == getuid()
    }
    public static func agentStatus() -> (running: Bool, pid: Int?) {
        guard let result = try? runProcess("/bin/launchctl", ["print", "gui/\(getuid())/\(BuildInfo.label)"]),
              result.code == 0 else { return (false, nil) }
        let pid = result.output.split(separator: "\n").compactMap { line -> Int? in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0] == "pid" ? Int(parts[1]) : nil
        }.first
        return (pid != nil, pid)
    }
    public static func openUI() throws {
        let result = try runProcess("/usr/bin/open", [BuildInfo.appPath])
        guard result.code == 0 else { throw BeepError.message(result.output) }
    }
}

/// AudioToolbox instead of a persistent AppKit/AVPlayer process.
public final class Beeper {
    private var sound: SystemSoundID = 0
    public init() throws {
        let binary = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let url = binary.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/beep.wav")
        let result = AudioServicesCreateSystemSoundID(url as CFURL, &sound)
        guard result == noErr else { throw BeepError.message("Cannot load alarm sound (\(result)): \(url.path)") }
    }
    public func play() { AudioServicesPlaySystemSound(sound) }
    deinit { AudioServicesDisposeSystemSoundID(sound) }
}

/// Watch the directory, not the file: atomic settings saves replace its inode.
public final class DirectoryWatch {
    private let source: DispatchSourceFileSystemObject
    public init(directory: URL, changed: @escaping () -> Void) throws {
        let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { throw BeepError.message("Cannot watch \(directory.path)") }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                    eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(fd) }
        source.resume()
    }
    deinit { source.cancel() }
}
#endif
