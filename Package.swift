// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Patchnap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Patchnap", targets: ["Patchnap"]),
        .executable(name: "patchnap-agent", targets: ["PatchnapAgent"]),
        .executable(name: "patchnap-store-helper", targets: ["PatchnapStoreHelper"])
    ],
    targets: [
        .target(name: "PatchnapCore"),
        .executableTarget(name: "Patchnap", dependencies: ["PatchnapCore"]),
        .executableTarget(name: "PatchnapAgent", dependencies: ["PatchnapCore"]),
        .executableTarget(name: "PatchnapStoreHelper", dependencies: ["PatchnapCore"]),
        .testTarget(name: "PatchnapCoreTests", dependencies: ["PatchnapCore"])
    ]
)
