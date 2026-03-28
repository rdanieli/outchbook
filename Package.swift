// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OuchBook",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "OuchBook",
            targets: ["OuchBook"]
        ),
        .executable(
            name: "OuchBookMenuBar",
            targets: ["OuchBookMenuBar"]
        ),
    ],
    targets: [
        .target(
            name: "OuchBook",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "OuchBookMenuBar",
            dependencies: ["OuchBook"]
        ),
        .testTarget(
            name: "OuchBookTests",
            dependencies: ["OuchBook"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
