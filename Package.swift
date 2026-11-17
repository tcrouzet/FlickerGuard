// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlickerGuard",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "FlickerGuard", resources: [.process("Resources")]),
        .testTarget(name: "FlickerGuardTests", dependencies: ["FlickerGuard"])
    ]
)
