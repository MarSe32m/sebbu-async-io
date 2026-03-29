// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "sebbu-async-io",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26)
    ],
    products: [
        .library(
            name: "SebbuAsyncIO",
            targets: ["SebbuAsyncIO"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MarSe32m/sebbu-iocp.git", branch: "main"),
        .package(url: "https://github.com/MarSe32m/sebbu-ts-ds.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.97.1")
    ],
    targets: [
        .target(
            name: "SebbuAsyncIO",
            dependencies: [
                .product(name: "SebbuIOCP", package: "sebbu-iocp"),
                .product(name: "SebbuTSDS", package: "sebbu-ts-ds"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "NIO", package: "swift-nio", condition: .when(platforms: [.linux, .macOS, .iOS, .watchOS, .tvOS]))
            ],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("LifetimeDependence")
            ]
        ),
        .executableTarget(
            name: "Development",
            dependencies: [
                "SebbuAsyncIO"
            ]
        ),
        .testTarget(
            name: "sebbu-async-ioTests",
            dependencies: ["SebbuAsyncIO"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
