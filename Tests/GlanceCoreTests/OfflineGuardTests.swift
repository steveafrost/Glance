import XCTest

/// Glance reads only local calendar data (EventKit) and never goes online.
/// There is no updater and no network entitlement, so the App Store build is
/// offline by construction. These tests read the source tree;
/// script/check-offline.sh runs the same checks plus a built app's signed
/// entitlements.
final class OfflineGuardTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func sources() throws -> [(String, String)] {
        let dir = root.appending(path: "Sources")
        let e = try XCTUnwrap(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
        return try e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            (String($0.path.dropFirst(root.path.count + 1)), try String(contentsOf: $0, encoding: .utf8))
        }
    }

    func testEntitlementsHaveNoNetworkAccess() throws {
        let ents = try read("Resources/Glance.entitlements")
        XCTAssertFalse(ents.contains("com.apple.security.network.client"))
        XCTAssertFalse(ents.contains("com.apple.security.network.server"))
        XCTAssertTrue(ents.contains("com.apple.security.app-sandbox"))
        // Any mach-lookup exception would widen what the sandbox can reach.
        XCTAssertFalse(ents.contains("temporary-exception.mach-lookup"))
    }

    /// No updater, so no feed and no EdDSA key to ship or keep secret.
    func testPlistHasNoUpdaterKeys() throws {
        let plist = try read("Resources/Info.plist")
        for key in ["SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks",
                    "SUEnableDownloaderService", "SUEnableInstallerLauncherService",
                    "SUEnableSystemProfiling"] {
            XCTAssertFalse(plist.contains("<key>\(key)</key>"), "Info.plist still ships \(key)")
        }
    }

    /// The App Store provides updates. A bundled updater is rejected, so a
    /// reintroduced Sparkle dependency should fail here rather than at review.
    func testNoThirdPartyDependencies() throws {
        let pkg = try read("Package.swift")
        XCTAssertEqual(pkg.components(separatedBy: ".package(url:").count - 1, 0, "Package.swift gained a dependency")
        XCTAssertFalse(pkg.contains("sparkle-project/Sparkle"), "Sparkle must not come back")
        for (path, text) in try sources() {
            XCTAssertFalse(text.contains("import Sparkle"), "\(path) imports Sparkle")
        }
    }

    func testSourcesUseNoNetworkingOrWebAPIs() throws {
        let banned = ["URLSession", "NSURLConnection", "NWConnection", "NWPathMonitor", "URLRequest",
                      "WKWebView", "WebView", "CFStream", "CFSocket", "Data(contentsOf: URL(string",
                      "String(contentsOf: URL(string"]
        let files = try sources()
        XCTAssertFalse(files.isEmpty)
        for (path, text) in files {
            for word in banned where text.contains(word) {
                XCTFail("\(path) uses \(word): Glance must stay offline")
            }
        }
    }

    func testOnlyAllowedFrameworksAreImported() throws {
        // No Network, WebKit, CloudKit, Contacts, etc. EventKit is the only data source.
        let allowed: Set<String> = ["AppKit", "Foundation", "EventKit", "Carbon.HIToolbox", "CoreGraphics",
                                    "CoreText", "QuartzCore", "ServiceManagement", "SwiftUI", "os",
                                    "GlanceCore"]
        let pattern = #"^\s*(?:@\w+\s+)*import\s+(?:class\s+|struct\s+|enum\s+|func\s+)?"#
            + #"([A-Za-z_][A-Za-z0-9_.]*)"#
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        for (path, text) in try sources() {
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertTrue(allowed.contains(name), "\(path) imports \(name)")
            }
        }
    }

    func testEventKitIsTheOnlyDataSource() throws {
        for (path, text) in try sources() where text.contains("EKEventStore(") {
            XCTAssertEqual(path, "Sources/Glance/EventRepository.swift", "\(path) creates its own event store")
        }
    }
}
