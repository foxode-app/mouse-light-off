// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseLightOff",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MouseLighting", targets: ["MouseLighting"]),
        .executable(name: "MouseLightOff", targets: ["MouseLightOff"]),
    ],
    targets: [
        .target(name: "MouseLighting"),
        .executableTarget(name: "MouseLightOff", dependencies: ["MouseLighting"]),
        .testTarget(name: "MouseLightingTests", dependencies: ["MouseLighting"]),
        .testTarget(name: "MouseLightOffTests", dependencies: ["MouseLightOff"]),
    ],
    swiftLanguageVersions: [.v5]
)
