// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DictateApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DictateApp",
            path: "Sources/DictateApp"
        )
    ]
)
