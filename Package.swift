// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SleepyHollow",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        // The library owns all behaviour; `sleepy` is its thin CLI consumer.
        // Deliberate naming: SleepyHollow + sleepy, overriding the usual
        // FooBarCore/FooBarCommand convention (see CLAUDE.md).
        .library(
            name: "SleepyHollow",
            targets: ["SleepyHollow"],
        ),
        .executable(
            name: "sleepy",
            targets: ["sleepy"],
        ),
    ],
    dependencies: [
        // Sole runtime dependency; swift-docc-plugin is docs tooling only.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "SleepyHollow",
        ),
        .target(
            name: "SleepyCLIKit",
            dependencies: [
                "SleepyHollow",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .executableTarget(
            name: "sleepy",
            dependencies: [
                "SleepyHollow",
                "SleepyCLIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .target(
            name: "TestSupport",
            dependencies: ["SleepyHollow"],
            path: "Tests/TestSupport",
            resources: [
                .copy("Fixtures"),
            ],
        ),
        .testTarget(
            name: "SleepyHollowTests",
            dependencies: ["SleepyHollow", "TestSupport", "SleepyCLIKit"],
        ),
        .testTarget(
            name: "SleepyGoldenTests",
            dependencies: ["SleepyHollow", "TestSupport"],
            exclude: ["README.md"],
        ),
    ],
    swiftLanguageModes: [.v6],
)
