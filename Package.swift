// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseScrollFlip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MouseScrollFlip", targets: ["MouseScrollFlip"])
    ],
    targets: [
        .target(
            name: "MouseScrollFlipCore",
            path: "Sources/MouseScrollFlipCore"
        ),
        .executableTarget(
            name: "MouseScrollFlip",
            dependencies: ["MouseScrollFlipCore"],
            path: "Sources/MouseScrollFlip"
        ),
        .testTarget(
            name: "MouseScrollFlipTests",
            dependencies: ["MouseScrollFlipCore"],
            path: "Tests/MouseScrollFlipTests"
        )
    ]
)
