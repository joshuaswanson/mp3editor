// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MP3Editor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MP3Editor", targets: ["MP3Editor"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MP3Editor",
            dependencies: []
        )
    ]
)
