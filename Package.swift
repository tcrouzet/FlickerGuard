// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PWMFixer",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "PWMFixer", resources: [.process("Resources")]),
        .testTarget(name: "PWMFixerTests", dependencies: ["PWMFixer"])
    ]
)
