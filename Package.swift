// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VTTSyncedVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VTTSyncedVoice",
            targets: ["VTTSyncedVoice"]
        ),
        .executable(
            name: "vtt-synced-voice",
            targets: ["VTTSyncedVoiceCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "VTTSyncedVoice",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "VTTSyncedVoiceCLI",
            dependencies: [
                "VTTSyncedVoice",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "VTTSyncedVoiceTests",
            dependencies: ["VTTSyncedVoice"]
        )
    ],
    swiftLanguageModes: [.v6]
)
