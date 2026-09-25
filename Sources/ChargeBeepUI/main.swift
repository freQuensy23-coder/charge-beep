#if os(macOS)
import AppKit
import ChargeBeepSettings

let app = NSApplication.shared
let delegate = SettingsApplication()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
#else
import Foundation
FileHandle.standardError.write(Data("Charge Beep UI requires macOS.\n".utf8))
#endif
