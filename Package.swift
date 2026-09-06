// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PeekBar",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "PeekBar", targets: ["PeekBar"]),
        .library(name: "PeekBarCore", targets: ["PeekBarCore"]),
    ],
    targets: [
        .target(
            name: "PeekBarCore",
            path: "Sources/PeekBarCore"
        ),
        .executableTarget(
            name: "PeekBar",
            dependencies: ["PeekBarCore"],
            path: "Sources/PeekBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "ScreenCaptureKit"]),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Metal"),
            ]
        ),
        .testTarget(
            name: "PeekBarCoreTests",
            dependencies: ["PeekBarCore"],
            path: "Tests/PeekBarCoreTests"
        ),
    ]
)
