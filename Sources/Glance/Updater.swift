import AppKit
import os
import Sparkle

/// Auto-update through Sparkle 2. Glance itself never goes online: it has no
/// network entitlement, and Sparkle's Downloader XPC service (inside
/// Sparkle.framework) fetches the appcast and the update, while its Installer
/// service installs it outside the sandbox. See Resources/Info.plist and
/// Resources/Glance.entitlements.
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    /// Posted when `automaticallyChecks`, `canCheck` or `availableVersion` may
    /// have changed.
    static let didChange = Notification.Name("GlanceUpdaterDidChange")

    private static let log = Logger(subsystem: "com.steveafrost.Glance", category: "updater")

    /// Nil until the build has a real feed URL (`GLANCE_FEED_URL`).
    private let controller: SPUStandardUpdaterController?
    /// Sparkle holds delegates weakly, so this has to stay alive here.
    private let driver: GentleReminderDriver?
    private var observation: NSKeyValueObservation?

    /// Set by the user driver delegate when a scheduled check finds an update
    /// it has not shown yet. Cleared once Sparkle has the user's attention or
    /// the session ends.
    private(set) var availableVersion: String?

    /// The build's appcast URL, or nil when it's still the placeholder.
    static var feedURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: s), url.scheme == "https",
              let host = url.host(), !host.hasSuffix(".invalid") else { return nil }
        return url
    }

    /// Whether this build can update itself (a real feed URL and a public key).
    ///
    /// This describes the *build*, not the run: a QA launch skips starting
    /// Sparkle, but the build it is running is still a configured one. Tying it
    /// to `controller` instead made Settings claim "This build has no update
    /// feed" in every docs screenshot.
    let isConfigured: Bool

    /// True while an update is known but hasn't been shown to the user.
    var hasQuietUpdate: Bool { availableVersion != nil }

    private override init() {
        let hasKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false
        isConfigured = Self.feedURL != nil && hasKey
        // QA runs never check for updates.
        let qa = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--qa") || $0 == "--keep-open" }
        if isConfigured, !qa {
            let driver = GentleReminderDriver()
            self.driver = driver
            controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: driver)
        } else {
            driver = nil
            controller = nil
        }
        super.init()
        driver?.owner = self
        observation = controller?.updater.observe(\.canCheckForUpdates) { _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: Updater.didChange, object: nil) }
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get {
            // Without a controller (a QA launch) there is no Sparkle to ask.
            // Report what the build would do: Sparkle defaults to on unless
            // SUEnableAutomaticChecks says otherwise, so the docs shots show the
            // switch as a user finds it.
            guard let controller else {
                let key = Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool
                return key ?? true
            }
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Brings a quietly-found update to the front, or checks when there is
    /// none. Either way the user ends up looking at Sparkle's window.
    @objc func checkForUpdates(_ sender: Any?) {
        // A menu bar app isn't active; bring Sparkle's window to the front.
        NSApp.activate()
        controller?.checkForUpdates(sender)
    }

    /// "Check for Updates…", or "Update to <version>…" once a scheduled check
    /// has found one.
    func menuItem() -> NSMenuItem {
        let title = availableVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
        let item = NSMenuItem(title: title, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        if !isConfigured { item.toolTip = "This build has no update feed" }
        return item
    }

    // MARK: Gentle reminders

    /// Called by the driver when a scheduled check finds an update. A menu bar
    /// app has no window to put a dialog in front of, so instead of opening a
    /// panel behind the user's work the menu item says what is waiting and the
    /// menu bar icon gains a badge.
    fileprivate func foundQuietUpdate(_ version: String) {
        guard availableVersion != version else { return }
        availableVersion = version
        Self.log.notice("quiet update available: \(version, privacy: .public)")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    fileprivate func clearQuietUpdate() {
        guard availableVersion != nil else { return }
        availableVersion = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

extension Updater: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates(_:)) ? canCheck : true
    }
}

/// Tells Sparkle that Glance handles scheduled update reminders itself.
///
/// Without this Sparkle logs that a background app "does not implement gentle
/// reminders" and shows its alert behind whatever the user is doing, where a
/// menu bar app's users will not see it.
///
/// A menu bar app has no window to put a dialog in front of, so the reminder
/// here is quiet: the menu item becomes "Update to <version>…". Nothing is
/// drawn into the menu bar icon, which always shows the date and nothing else.
/// No panel appears until the user acts on the menu item.
///
/// That means always handling the presentation ourselves, immediate focus
/// included: `immediateFocus` means Sparkle thinks it may present in "utmost
/// focus", but for a background app it shows the alert behind whatever the user
/// is doing, which is how the update goes unnoticed in the first place.
@MainActor
private final class GentleReminderDriver: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var owner: Updater?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                             andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        owner?.foundQuietUpdate(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        owner?.clearQuietUpdate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        owner?.clearQuietUpdate()
    }
}
