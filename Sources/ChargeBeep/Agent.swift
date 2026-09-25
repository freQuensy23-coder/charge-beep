#if os(macOS)
import Foundation
import CoreFoundation
import SystemConfiguration
import IOKit.ps
import ChargeBeepCore

final class Agent {
    private let store = ConfigStore()
    private var settings = Settings()
    private var alarm = Alarm()
    private var beeper: Beeper?
    private var lock: FileLock?
    private var watch: DirectoryWatch?
    private var powerSource: CFRunLoopSource?
    private var sessionStore: SCDynamicStore?
    private var timer: Timer?

    func start() throws {
        try store.prepare()
        lock = try FileLock(url: store.directory.appendingPathComponent("agent.lock"), nonBlocking: true)
        watch = try DirectoryWatch(directory: store.directory) { [weak self] in self?.refresh() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<Agent>.fromOpaque(context).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue() else { throw BeepError.message("Cannot subscribe to battery changes.") }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        var sessionContext = SCDynamicStoreContext(version: 0, info: context, retain: nil, release: nil, copyDescription: nil)
        let key = SCDynamicStoreKeyCreateConsoleUser(nil)
        guard let session = SCDynamicStoreCreate(nil, BuildInfo.label as CFString, { _, _, context in
            guard let context else { return }
            Unmanaged<Agent>.fromOpaque(context).takeUnretainedValue().refresh()
        }, &sessionContext),
              SCDynamicStoreSetNotificationKeys(session, [key] as CFArray, nil),
              SCDynamicStoreSetDispatchQueue(session, .main) else {
            throw BeepError.message("Cannot subscribe to user-session changes.")
        }
        sessionStore = session
        refresh()
    }
    func refresh() {
        // Invalid edits do not silently reset the user's last known good settings.
        do { settings = try store.load() } catch { logError(error) }
        let now = ProcessInfo.processInfo.systemUptime
        if alarm.evaluate(battery: Mac.battery(), settings: settings,
                          activeUser: Mac.isActiveUser(), now: now) {
            do {
                if beeper == nil { beeper = try Beeper() }
                beeper?.play()
            } catch { logError(error) }
        }
        if alarm.nextBeep == nil { beeper = nil }
        timer?.invalidate()
        timer = nil
        if let deadline = alarm.nextBeep {
            // No repeating timer or battery polling when no alarm is active.
            let timer = Timer(timeInterval: max(0.05, deadline - now), repeats: false) { [weak self] _ in
                self?.refresh()
            }
            timer.tolerance = 0.2
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    deinit {
        timer?.invalidate()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        if let sessionStore { SCDynamicStoreSetDispatchQueue(sessionStore, nil) }
    }
}
#endif
