// swift-tools-version: 6.2
import PackageDescription

// Split so the logic builds and tests from the command line — on CI, without
// Xcode or a simulator. `AIPulseCore` imports neither SwiftUI nor UIKit;
// `AIPulseUI` holds the views as a library over a thin app entry point.
let package = Package(
    name: "AIPulse",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AIPulseCore", targets: ["AIPulseCore"]),
        .library(name: "AIPulseUI", targets: ["AIPulseUI"])
    ],
    targets: [
        .target(name: "AIPulseCore"),
        .target(name: "AIPulseUI", dependencies: ["AIPulseCore"]),
        .testTarget(
            name: "AIPulseCoreTests",
            dependencies: ["AIPulseCore"]
        ),
        .testTarget(
            name: "AIPulseUITests",
            dependencies: ["AIPulseUI", "AIPulseCore"]
        )
    ]
)
