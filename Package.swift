// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "TwoFingerDrag",
    platforms: [
        .macOS(.v13) // MenuBarExtra доступен с macOS 13 Ventura
    ],
    targets: [
        .executableTarget(
            name: "TwoFingerDrag",
            path: "Sources/TwoFingerDrag"
        )
    ]
)
