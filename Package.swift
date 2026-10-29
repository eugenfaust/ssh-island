// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SSHIsland",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "SSHIsland", targets: ["SSHIsland"])],
    targets: [
        .target(name: "SSHIslandCore"),
        .executableTarget(name: "SSHIsland", dependencies: ["SSHIslandCore"]),
        .executableTarget(name: "SSHIslandTests", dependencies: ["SSHIslandCore"], path: "Tests/SSHIslandCoreTests")
    ], swiftLanguageModes: [.v6]
)
