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
            path: "Sources/AutoNovelStudio",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "AutoNovelStudioTests",
            dependencies: ["AutoNovelStudio"],
            path: "tests/AutoNovelStudioTests"
        ),
    ]
)
