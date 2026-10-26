import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    migrateLegacySandboxPreferences()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// Direct GitHub distributions must be able to replace their app bundle.
  /// Preserve preferences from the formerly sandboxed preview on first launch.
  private func migrateLegacySandboxPreferences() {
    let defaults = UserDefaults.standard
    let marker = "promptboxLegacyPreferencesImported"
    guard !defaults.bool(forKey: marker),
          let identifier = Bundle.main.bundleIdentifier else { return }
    let legacy = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("Containers")
      .appendingPathComponent(identifier)
      .appendingPathComponent("Data/Library/Preferences")
      .appendingPathComponent("\(identifier).plist")
    if let data = try? Data(contentsOf: legacy),
       let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
      for (key, value) in values where key.hasPrefix("flutter.") {
        if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
      }
    }
    defaults.set(true, forKey: marker)
  }
}
