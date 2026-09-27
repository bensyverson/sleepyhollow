# The "linked against old SDK" inspection notice (2026-09-26)

Findings for job leaf PqG17l. On macOS 27 (Xcode 27, Swift 6.4, SDK 27.0) every golden test that asserts an empty stderr failed — on a clean `main` too — because each page load in the debug `sleepy` printed:

> Inspection is enabled by default for process or parent application with 'com.apple.security.get-task-allow' entitlement linked against old SDK. Use `inspectable` API to enable inspection on newer SDKs.

## The cause: the link records the deployment floor as the SDK

The notice is WebKit's linked-on-or-after check: a process whose main executable claims an SDK older than the one that made `WKWebView` non-inspectable by default, *and* that carries `get-task-allow` (every debug build), gets inspection on and the notice. The package does **not** build against an old SDK — the binary only says it does:

```
$ otool -l .build/debug/sleepy | grep -A4 LC_BUILD_VERSION
 platform 1
    minos 12.0
      sdk 12.0        ← should be 27.0
```

Every object file carries `sdk 27.0`; only the final link loses it. The chain, each link checked by hand on this machine:

1. SwiftPM's default build system is now Swift Build. Its `Ld` task (in `.build/out/Intermediates.noindex/XCBuildData/*.xcbuilddata/manifest.json`) runs `swiftc -target arm64-apple-macos12.0 -sdk …/MacOSX27.0.sdk -emit-executable …`, with no `$SDKROOT` in the task's environment — setting `SDKROOT` on the `swift build` command line does not reach it.
2. `swiftc` hands the SDK to clang as `--sysroot`.
3. Apple clang takes the SDK *version* for `ld -platform_version` only from `-isysroot` or `$SDKROOT`, never from `--sysroot`: `clang -### x.o --sysroot $SDK --target=arm64-apple-macos12.0` passes `-platform_version macos 12.0.0 12.0.0`; the same with `-isysroot $SDK` passes `12.0.0 27.0`.
4. So `ld` writes `sdk 12.0`.

The same package built with `--build-system native`, or linked by `xcrun swiftc` (the shim exports `SDKROOT`), records `sdk 27.0` and prints nothing. A one-file executable package built with plain `swift build` reproduces the `sdk 12.0` — it is not specific to SleepyHollow.

## What does not work

- `webView.isInspectable = false` after init (tried before this leaf): the notice still prints. It answers the wrong question anyway — the binary is not asking for inspection, it is misreporting its SDK.
- `SDKROOT=… swift build`: Swift Build does not pass it to the link.
- `linkerSettings: [.unsafeFlags([… "$(SDKROOT)"])]`: the manifest refuses `$(…)` in unsafe flags ("contains invalid component(s)").

## The fix

`Package.swift` reads `$SDKROOT` from the manifest's own environment (`Context.environment` — the `swift` shim exports it) and gives the `sleepy` executable `-Xclang-linker -isysroot -Xclang-linker <that SDK>`. The link then records `sdk 27.0`, WebKit applies the current SDK's behaviour (inspection off by default), and the notice is gone. The declared floor, `.macOS(.v12)`, is untouched — `minos` stays 12.0. With no `$SDKROOT` the flag is simply absent and the build is exactly what it was.

The flag is on the executable target only, so a package that depends on SleepyHollow's library never sees an unsafe flag; a scratch consumer resolved it both as a branch and as a version dependency.

Not taken: stripping `get-task-allow` (only a `swift build` flag, `--disable-get-task-allow-entitlement`, which the pre-commit hook's plain `swift test` cannot pass, and it would cost debugger attach), raising the floor (a public-API decision, and unnecessary), and filtering the line from captured stderr (hides the symptom, leaves `sleepy` claiming the wrong SDK).

## Reproduce

```
swift build --package-path .
otool -l .build/debug/sleepy | grep -A4 LC_BUILD_VERSION     # sdk 27.0 with the fix, 12.0 without
swift test --filter "LoadGoldenTests|DoctorGoldenTests"      # red without the fix: the notice in stderr
```

The fix covers `sleepy` only. Any other executable built by Swift Build with a macOS floor below the SDK records the floor as its SDK too; whether an embedder's binaries see the notice was not examined.
