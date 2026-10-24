// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nightforge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nightforge",
            path: "Sources/Nightforge"
        )
    ]
)
