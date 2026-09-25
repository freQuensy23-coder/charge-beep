#if os(macOS)
import AppKit
import ChargeBeepCore

public final class SettingsApplication: NSObject, NSApplicationDelegate {
    public let settings = SettingsWindow()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        settings.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.showWindow(nil)
        return true
    }
}

public final class SettingsWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let store = ConfigStore()
    private let threshold = NSTextField(string: "1")
    private let stepper = NSStepper()
    private let enabled = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private var watch: DirectoryWatch?
    private var beeper: Beeper?

    public init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 116),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Charge Beep"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.initialFirstResponder = enabled

        threshold.alignment = .right
        threshold.delegate = self
        threshold.identifier = NSUserInterfaceItemIdentifier("threshold")
        threshold.setAccessibilityIdentifier("threshold")
        threshold.setAccessibilityLabel("Battery threshold percent")
        threshold.widthAnchor.constraint(equalToConstant: 44).isActive = true
        stepper.minValue = 1
        stepper.maxValue = 100
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(step)
        stepper.identifier = NSUserInterfaceItemIdentifier("threshold-stepper")
        stepper.setAccessibilityIdentifier("threshold-stepper")
        enabled.target = self
        enabled.action = #selector(toggle)
        enabled.identifier = NSUserInterfaceItemIdentifier("enabled")
        enabled.setAccessibilityIdentifier("enabled")
        let test = NSButton(title: "Test sound", target: self, action: #selector(testSound))
        test.bezelStyle = .rounded
        test.identifier = NSUserInterfaceItemIdentifier("test-sound")
        test.setAccessibilityIdentifier("test-sound")

        let valueRow = NSStackView(views: [NSTextField(labelWithString: "Beep at"), NSView(),
                                         threshold, NSTextField(labelWithString: "%"), stepper])
        let actionRow = NSStackView(views: [enabled, NSView(), test])
        let stack = NSStackView(views: [valueRow, actionRow])
        stack.orientation = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            valueRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center()
        do {
            try store.prepare()
            watch = try DirectoryWatch(directory: store.directory) { [weak self] in self?.reload() }
            reload()
        } catch { show(error) }
    }

    required init?(coder: NSCoder) { return nil }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Commit the field editor before the settings process exits.
        sender.makeFirstResponder(nil)
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let n = Int(threshold.stringValue), (1...100).contains(n) else {
            reload()
            show(BeepError.message("Enter a whole number from 1 to 100."))
            return
        }
        save { $0.threshold = n }
    }

    @objc private func step() { save { $0.threshold = stepper.integerValue } }
    @objc private func toggle() { save { $0.enabled = enabled.state == .on } }

    @objc private func testSound() {
        do {
            if beeper == nil { beeper = try Beeper() }
            beeper?.play()
        } catch { show(error) }
    }

    private func save(_ change: (inout Settings) -> Void) {
        do { try store.update(change); reload() }
        catch { show(error) }
    }

    private func reload() {
        do {
            let value = try store.load()
            if threshold.currentEditor() == nil { threshold.stringValue = String(value.threshold) }
            stepper.integerValue = value.threshold
            enabled.state = value.enabled ? .on : .off
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        guard let window, window.attachedSheet == nil else { logError(error); return }
        let alert = NSAlert()
        alert.messageText = String(describing: error)
        alert.beginSheetModal(for: window)
    }
}
#endif
