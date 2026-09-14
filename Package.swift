// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AutoNovelStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AutoNovelStudio", targets: ["AutoNovelStudio"]),
    ],
    targets: [
        .executableTarget(
            name: "AutoNovelStudio",
            path: "Sources/AutoNovelStudio"
        ),
        .testTarget(
            name: "AutoNovelStudioTests",
            dependencies: ["AutoNovelStudio"],
            path: "Tests/AutoNovelStudioTests"
        ),
    ]
)
