// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenTimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OpenTimer",
            path: "Sources/OpenTimer"
        )
    ]
)
