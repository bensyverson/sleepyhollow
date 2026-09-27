// swift-tools-version: 6.3

import PackageDescription

/// Makes `sleepy`'s link record the SDK it was built against, not the
/// deployment floor.
///
/// SwiftPM's default build system (Swift Build, since Swift 6.4) links
/// through `swiftc`, which hands clang the SDK as `--sysroot`; Apple clang
/// reads the SDK *version* only from `-isysroot` or `$SDKROOT`, and Swift
/// Build runs the link without `$SDKROOT`. So `ld` is told
/// `-platform_version macos 12.0 12.0` and the binary claims to be built
/// against the macOS 12 SDK (`otool -l`: `sdk 12.0`). WebKit gates its
/// linked-on-or-after behaviours on that field: an "old-SDK" binary signed
/// with `get-task-allow` — every debug build — is inspectable by default and
/// prints a notice to stderr on every page load. The manifest runs under the
/// `xcrun` shim's `$SDKROOT`, so it hands the same SDK to clang as
/// `-isysroot`. The declared floor (`.macOS(.v12)`) is untouched.
/// See project/2026-09-26-old-sdk-inspection-notice.md.
let sdkVersionLinkerSettings: [LinkerSetting] = Context.environment["SDKROOT"].map { sdk in
    [.unsafeFlags(["-Xclang-linker", "-isysroot", "-Xclang-linker", sdk], .when(platforms: [.macOS]))]
} ?? []

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
            linkerSettings: sdkVersionLinkerSettings,
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
