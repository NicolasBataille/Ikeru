// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IkeruCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "IkeruCore",
            targets: ["IkeruCore"]
        )
    ],
    targets: [
        .target(
            name: "IkeruCore",
            path: "Sources"
        ),
        .testTarget(
            name: "IkeruCoreTests",
            dependencies: ["IkeruCore"],
            path: "Tests"
        )
    ]
)
