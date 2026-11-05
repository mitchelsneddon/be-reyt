// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ReytKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "ReytKit", targets: ["ReytKit"])
    ],
    targets: [
        .target(name: "ReytKit"),
        .testTarget(name: "ReytKitTests", dependencies: ["ReytKit"]),
    ],
    swiftLanguageModes: [.v6]
)
