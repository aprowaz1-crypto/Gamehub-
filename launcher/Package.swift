// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GamehubLauncher",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "GamehubLauncher", targets: ["GamehubLauncher"]),
    ],
    targets: [
        .target(name: "GamehubLauncher"),
        .testTarget(name: "GamehubLauncherTests", dependencies: ["GamehubLauncher"]),
    ]
)
