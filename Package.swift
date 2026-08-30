// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Throttle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Throttle",
            path: "Sources/Throttle",
            resources: [.copy("Resources/Brand")]
        ),
        .testTarget(
            name: "ThrottleTests",
            dependencies: ["Throttle"],
            path: "Tests/ThrottleTests"
        )
    ]
)
