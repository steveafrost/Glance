import AppKit
import Sparkle

/// Auto-update through Sparkle 2. Glance itself never goes online: it has no
/// network entitlement, and Sparkle's Downloader XPC service (inside
/// Sparkle.framework) fetches the appcast and the update, while its Installer
/// service installs it outside the sandbox. See Resources/Info.plist and
/// Resources/Glance.entitlements.
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    /// Posted when `automaticallyChecks` or `canCheck` may have changed.
    static let didChange = Notification.Name("GlanceUpdaterDidChange")

    /// Nil until the build has a real feed URL (`GLANCE_FEED_URL`).
    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    /// The build's appcast URL, or nil when it's still the placeholder.
    static var feedURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: s), url.scheme == "https",
              let host = url.host(), !host.hasSuffix(".invalid") else { return nil }
        return url
    }

    /// Whether this build can update itself (a real feed URL and a public key).
    var isConfigured: Bool { controller != nil }

    private override init() {
        let hasKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false
        // QA runs never check for updates.
        let qa = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--qa") || $0 == "--keep-open" }
        if Self.feedURL != nil, hasKey, !qa {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        super.init()
        observation = controller?.updater.observe(\.canCheckForUpdates) { _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: Updater.didChange, object: nil) }
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        // A menu bar app isn't active; bring Sparkle's window to the front.
        NSApp.activate()
        controller?.checkForUpdates(sender)
    }

    /// "Check for Updates…", disabled when this build can't update.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        if !isConfigured { item.toolTip = "This build has no update feed" }
        return item
    }
}

extension Updater: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates(_:)) ? canCheck : true
    }
}
