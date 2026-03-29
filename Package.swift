// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sandevistan",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sandevistan",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
            ]
        )
    ]
)
