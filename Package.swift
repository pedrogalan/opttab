// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OptTab",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OptTab",
            path: "Sources/OptTab"
        )
    ]
)
