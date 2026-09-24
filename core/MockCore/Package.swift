// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GamehubMockCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "GamehubMockCore", targets: ["GamehubMockCore"]),
    ],
    targets: [
        .target(
            name: "GamehubMockCore",
            path: "Sources/GamehubMockCore"
        ),
        .testTarget(
            name: "GamehubMockCoreTests",
            dependencies: ["GamehubMockCore"],
            path: "Tests/GamehubMockCoreTests"
        ),
    ]
)
