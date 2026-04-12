// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppIconGen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AppIconGen", path: "Sources")
    ]
)
