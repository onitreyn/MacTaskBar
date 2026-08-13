// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskbarApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TaskbarApp",
            path: "Sources/TaskbarApp"
        )
    ]
)
