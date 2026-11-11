// swift-tools-version: 6.0
// Xcode で開く用。ビルドは scripts/build-app.sh（swiftc を直接使う）。
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Koe", path: "Sources/Koe"),
        .testTarget(name: "KoeTests", dependencies: ["Koe"], path: "Tests/KoeTests"),
    ],
    swiftLanguageModes: [.v5]
)
