// swift-tools-version: 6.0
import PackageDescription

// The client side of the Mac's FU Mail API: the models (copied from the Mac app's FUMailCore, so the
// JSON is Swift's own Codable on both ends), the rules, the state kept from the event stream, and the
// client. No dependencies. It builds for iOS (the app) and for macOS too, so `swift test` runs the
// tests on the Mac without a simulator.

let package = Package(
    name: "FUMailKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FUMailKit", targets: ["FUMailKit"])
    ],
    targets: [
        .target(name: "FUMailKit"),
        .testTarget(name: "FUMailKitTests", dependencies: ["FUMailKit"], resources: [.copy("Fixtures")]),
    ]
)
