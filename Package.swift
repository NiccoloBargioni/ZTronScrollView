// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZTronScrollView",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "ZTronScrollView", targets: ["ZTronScrollView"]),
    ],
    dependencies: [
        .package(path: "Packages/ZTronScrollPhysics"),
        // Path dependency until ScrollArbitration is pushed to its own repository; then
        // `.package(url: "<repo>", .upToNextMinor(from: "1.0.0"))` (SPEC S16).
        .package(path: "Packages/ScrollArbitration"),
    ],
    targets: [
        .target(
            name: "ZTronScrollView",
            dependencies: [
                .product(name: "ZTronScrollPhysics", package: "ZTronScrollPhysics"),
                .product(name: "ScrollArbitration", package: "ScrollArbitration"),
            ]
        ),
        .testTarget(
            name: "ZTronScrollViewTests",
            dependencies: ["ZTronScrollView"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
