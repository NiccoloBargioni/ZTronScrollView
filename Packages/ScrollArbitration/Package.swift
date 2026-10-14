// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrollArbitration",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ScrollArbitration", targets: ["ScrollArbitration"]),
    ],
    targets: [
        .target(name: "ScrollArbitration"),
        .testTarget(name: "ScrollArbitrationTests", dependencies: ["ScrollArbitration"]),
    ],
    swiftLanguageModes: [.v6]
)
