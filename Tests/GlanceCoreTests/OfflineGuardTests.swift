import XCTest

/// Glance reads only local calendar data (EventKit) and never goes online.
/// Sparkle's Downloader XPC service does update fetching outside the app
/// process, so the app itself must never gain network access. These tests
/// read the source tree; script/check-offline.sh runs the same checks plus a
/// built app's signed entitlements.
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
        // Sparkle's Downloader service is what keeps the app offline.
        let plist = try read("Resources/Info.plist")
        XCTAssertTrue(plist.contains("<key>SUEnableDownloaderService</key>\n    <true/>"))
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
                                    "GlanceCore", "Sparkle"]
        let regex = try NSRegularExpression(pattern: #"^\s*(?:@\w+\s+)*import\s+(?:class\s+|struct\s+|enum\s+|func\s+)?([A-Za-z_][A-Za-z0-9_.]*)"#,
                                            options: .anchorsMatchLines)
        for (path, text) in try sources() {
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertTrue(allowed.contains(name), "\(path) imports \(name)")
                if name == "Sparkle" { XCTAssertEqual(path, "Sources/Glance/Updater.swift", "keep Sparkle in Updater.swift") }
            }
        }
    }

    func testEventKitIsTheOnlyDataSource() throws {
        for (path, text) in try sources() where text.contains("EKEventStore(") {
            XCTAssertEqual(path, "Sources/Glance/EventRepository.swift", "\(path) creates its own event store")
        }
        // Sparkle is the only package dependency.
        let pkg = try read("Package.swift")
        let deps = pkg.components(separatedBy: ".package(url:").count - 1
        XCTAssertEqual(deps, 1)
        XCTAssertTrue(pkg.contains("sparkle-project/Sparkle"))
    }
}
