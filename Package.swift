// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nachtschicht",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nachtschicht",
            path: "Sources/Nachtschicht"
        )
    ]
)
