// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZTronScrollPhysics",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ZTronScrollPhysics", targets: ["ZTronScrollPhysics"]),
    ],
    targets: [
        .target(name: "ZTronScrollPhysics"),
        .testTarget(name: "ZTronScrollPhysicsTests", dependencies: ["ZTronScrollPhysics"]),
    ],
    swiftLanguageModes: [.v6]
)
