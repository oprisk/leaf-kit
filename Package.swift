// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "leaf-kit",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "LeafKit", targets: ["LeafKit"]),
        .library(name: "XCTLeafKit", targets: ["XCTLeafKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.20.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LeafKit", dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio")
            ]),
        .target(name: "XCTLeafKit", dependencies: [
            .target(name: "LeafKit")
        ]),
        .testTarget(
            name: "LeafKitTests",
            dependencies: ["XCTLeafKit"]),
    ]
)
