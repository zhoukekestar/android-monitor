// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "phase0-spike",
            targets: ["MacHost"]
        ),
        .executable(
            name: "android-monitor-host",
            targets: ["MacHostMenu"]
        ),
        .executable(
            name: "status-panel-server",
            targets: ["MacStatusPanel"]
        ),
        .library(
            name: "MacHostMenuCore",
            targets: ["MacHostMenuCore"]
        )
    ],
    targets: [
        .target(
            name: "MacHostMenuCore",
            path: "Sources/MacHostMenuCore"
        ),
        .executableTarget(
            name: "MacHost",
            path: "Sources/MacHost",
            cSettings: [
                .unsafeFlags(["-I", "Sources/MacHost"])
            ],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-fmodule-map-file=Sources/MacHost/module.modulemap"])
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Network"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .executableTarget(
            name: "MacHostMenu",
            dependencies: ["MacHostMenuCore"],
            path: "Sources/MacHostMenu",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "MacStatusPanel",
            path: "Sources/MacStatusPanel",
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .testTarget(
            name: "MacHostMenuCoreTests",
            dependencies: ["MacHostMenuCore"],
            path: "Tests/MacHostMenuCoreTests"
        )
    ]
)
