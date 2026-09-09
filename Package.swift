// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LingDesktop", targets: ["LingDesktop"])],
    targets: [
        .target(name: "LingCore"),
        .executableTarget(name: "LingDesktop", dependencies: ["LingCore"]),
        .executableTarget(name: "LingCoreChecks", dependencies: ["LingCore"], path: "Tests/LingCoreTests")
    ]
)
