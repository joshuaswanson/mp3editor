// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MP3Editor",
    platforms: [.macOS(.v26)],
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
