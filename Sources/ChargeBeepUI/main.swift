#if os(macOS)
import AppKit
import ChargeBeepCore

final class SettingsApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private let store = ConfigStore()
    private var window: NSWindow!
    private let threshold = NSTextField(string: "1")
    private let stepper = NSStepper()
    private let enabled = NSButton(checkboxWithTitle: "Звуковой сигнал", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private var watch: DirectoryWatch?
    private var beeper: Beeper?
    #if DEBUG
    private var testResult: URL?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 190),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Charge Beep"
        window.isReleasedWhenClosed = false
        window.delegate = self
        threshold.alignment = .right
        threshold.delegate = self
        threshold.setAccessibilityIdentifier("threshold")
        threshold.widthAnchor.constraint(equalToConstant: 48).isActive = true
        stepper.minValue = 1; stepper.maxValue = 100; stepper.increment = 1
        stepper.target = self; stepper.action = #selector(step)
        stepper.setAccessibilityIdentifier("threshold-stepper")
        enabled.target = self; enabled.action = #selector(toggle)
        enabled.setAccessibilityIdentifier("enabled")
        let row = NSStackView(views: [NSTextField(labelWithString: "Сигнал при заряде"), threshold,
                                      NSTextField(labelWithString: "%"), stepper])
        row.spacing = 8
        let test = NSButton(title: "Проверить звук", target: self, action: #selector(testSound))
        test.bezelStyle = .rounded
        test.setAccessibilityIdentifier("test-sound")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        let stack = NSStackView(views: [row, enabled, test, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)
        ])
        do {
            try store.prepare()
            watch = try DirectoryWatch(directory: store.directory) { [weak self] in self?.reload() }
            reload()
        } catch { show(error) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #if DEBUG
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2 && args[0] == "_test-ui" {
            testResult = URL(fileURLWithPath: args[1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.exerciseWindow() }
        }
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    func controlTextDidEndEditing(_ notification: Notification) { saveThreshold() }
    @objc private func step() {
        threshold.stringValue = String(stepper.integerValue)
        saveThreshold()
    }
    private func saveThreshold() {
        do {
            guard let n = Int(threshold.stringValue) else {
                throw BeepError.message("Введите целое число от 1 до 100.")
            }
            try store.update { $0.threshold = n }
            reload()
        } catch { show(error); reload() }
    }
    @objc private func toggle() {
        do { try store.update { $0.enabled = enabled.state == .on }; reload() }
        catch { show(error); reload() }
    }
    @objc private func testSound() {
        do { if beeper == nil { beeper = try Beeper() }; beeper?.play() }
        catch { show(error) }
    }
    private func reload() {
        do {
            let value = try store.load()
            // A file notification must not overwrite text being edited.
            if window.firstResponder !== threshold.currentEditor() {
                threshold.stringValue = String(value.threshold)
            }
            stepper.integerValue = value.threshold
            enabled.state = value.enabled ? .on : .off
            status.stringValue = Mac.agentStatus().running
                ? "Работает в фоне · версия \(BuildInfo.version)"
                : "Фоновый процесс не запущен. Проверьте автозагрузку."
        } catch { status.stringValue = "Ошибка чтения настроек: \(error)" }
    }
    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Charge Beep"
        alert.informativeText = String(describing: error)
        alert.beginSheetModal(for: window)
    }
    #if DEBUG
    // In-process UI driver: operates real AppKit controls and closes the real window.
    // No test switches exist in release builds. Process E2E separately verifies launchd survives.
    private func exerciseWindow() {
        do {
            threshold.stringValue = "7"
            controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
            guard try store.load().threshold == 7 else { throw BeepError.message("UI threshold did not persist") }
            stepper.integerValue = 8; stepper.sendAction(stepper.action, to: self)
            guard try store.load().threshold == 8 else { throw BeepError.message("Stepper did not persist") }
            enabled.state = .on; enabled.performClick(nil)
            guard try !store.load().enabled else { throw BeepError.message("Toggle did not persist") }
            enabled.performClick(nil)
            guard try store.load().enabled else { throw BeepError.message("Toggle did not re-enable") }
            window.performClose(nil)
        } catch {
            if let testResult { try? Data("FAIL: \(error)".utf8).write(to: testResult) }
            NSApplication.shared.terminate(nil)
        }
    }
    func windowWillClose(_ notification: Notification) {
        if let testResult { try? Data("PASS: threshold, stepper, enabled, window close".utf8).write(to: testResult) }
    }
    #endif
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = SettingsApp()
app.delegate = delegate
app.run()
#else
import Foundation
FileHandle.standardError.write(Data("Charge Beep UI requires macOS.\n".utf8))
#endif
