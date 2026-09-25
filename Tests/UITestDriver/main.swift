#if os(macOS)
import AppKit
import ChargeBeepCore
import ChargeBeepSettings

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw BeepError.message(message) }
}

func find<T: NSView>(_ id: String, in root: NSView) throws -> T {
    if root.identifier?.rawValue == id, let view = root as? T { return view }
    for child in root.subviews {
        if let view: T = try? find(id, in: child) { return view }
    }
    throw BeepError.message("Missing control: \(id)")
}

@MainActor
func waitUntil(_ description: String, _ condition: () -> Bool) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !condition() {
        guard Date() < deadline else { throw BeepError.message("Timed out: \(description)") }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

func edit(_ field: NSTextField, _ text: String) throws {
    field.selectText(nil)
    guard let editor = field.currentEditor() as? NSTextView else {
        throw BeepError.message("Threshold field did not begin editing")
    }
    editor.string = text
    editor.didChangeText()
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else { fatalError("Usage: ChargeBeepUITestDriver CLI RESULT_PATH") }
let resultFile = URL(fileURLWithPath: args[1])
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = SettingsApplication()
app.delegate = delegate

Task { @MainActor in
    do {
        guard let window = delegate.settings.window, let content = window.contentView else {
            throw BeepError.message("Settings window is missing")
        }
        let field: NSTextField = try find("threshold", in: content)
        let stepper: NSStepper = try find("threshold-stepper", in: content)
        let enabled: NSButton = try find("enabled", in: content)
        let store = ConfigStore()
        try await waitUntil("settings window") { window.isVisible }

        content.layoutSubtreeIfNeeded()
        guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw BeepError.message("Cannot capture settings window")
        }
        content.cacheDisplay(in: content.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw BeepError.message("Cannot encode settings screenshot")
        }
        try png.write(to: resultFile.appendingPathExtension("png"))

        // An external CLI write must reach the open window through DirectoryWatch.
        let changed = try runProcess(args[0], ["set", "threshold", "9"])
        try require(changed.code == 0, changed.output)
        try await waitUntil("CLI threshold in UI") { field.stringValue == "9" && stepper.integerValue == 9 }

        // File events must not discard a value still in the field editor.
        try edit(field, "6")
        let disabled = try runProcess(args[0], ["set", "enabled", "false"])
        try require(disabled.code == 0, disabled.output)
        try await waitUntil("CLI enable state in UI") { enabled.state == .off }
        try require(field.currentEditor()?.string == "6", "File notification discarded the active edit")
        try require(window.makeFirstResponder(enabled), "Threshold could not finish editing")
        try require(try store.load().threshold == 6, "Edited threshold was not saved")
        try require(try !store.load().enabled, "Threshold edit overwrote the CLI enable setting")

        stepper.integerValue = 7
        try require(stepper.sendAction(stepper.action, to: stepper.target), "Stepper action is disconnected")
        try require(try store.load().threshold == 7, "Stepper did not save its value")
        enabled.performClick(nil)
        try require(try store.load().enabled, "Enable switch did not save its value")

        // Closing with a live editor must persist the edit before the process exits.
        try edit(field, "8")
        window.performClose(nil)
        try require(!window.isVisible, "Window did not close")
        try require(try store.load().threshold == 8, "Closing the window lost the threshold edit")
        try Data("PASS\n".utf8).write(to: resultFile)
    } catch {
        logError(error)
        exit(1)
    }
}
app.run()
#else
import Foundation
FileHandle.standardError.write(Data("UI integration tests require macOS.\n".utf8))
#endif
