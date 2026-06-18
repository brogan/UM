// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UMEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UMEngine", targets: ["UMEngine"])
    ],
    dependencies: [
        .package(path: "../../Loom_2026/loom_swift")
    ],
    targets: [
        .target(
            name: "UMEngine",
            dependencies: [
                .product(name: "LoomEngine", package: "loom_swift")
            ],
            path: "Sources/UMEngine"
        )
    ]
)
