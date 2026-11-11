// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Glance", targets: ["Glance"]),
    ],
    dependencies: [],
    targets: [
        // Pure, AppKit-free logic: date math, parsing, layout geometry, caching.
        .target(
            name: "GlanceCore",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        // The AppKit app.
        .executableTarget(
            name: "Glance",
            dependencies: ["GlanceCore"],
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
