// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Glance", targets: ["Glance"]),
    ],
    dependencies: [
        // Auto-update only. Glance has no other third-party code.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure, AppKit-free logic: date math, parsing, layout geometry, caching.
        .target(
            name: "GlanceCore",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        // The AppKit app.
        .executableTarget(
            name: "Glance",
            dependencies: ["GlanceCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "GlanceCoreTests",
            dependencies: ["GlanceCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
