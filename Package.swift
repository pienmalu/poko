// swift-tools-version: 6.0
// Xcode で開く用。ビルドは scripts/build-app.sh（swiftc を直接使う）。
import PackageDescription

let package = Package(
    name: "Poko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Poko", path: "Sources/Poko"),
        .testTarget(name: "PokoTests", dependencies: ["Poko"], path: "Tests/PokoTests"),
    ],
    swiftLanguageModes: [.v5]
)
