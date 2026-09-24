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
        .target(name: "GamehubMockCore"),
        .testTarget(name: "GamehubMockCoreTests", dependencies: ["GamehubMockCore"]),
    ]
)
