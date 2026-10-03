// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "laiaskills",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "laiaskills", targets: ["laiaskills"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/tuist/Noora", .upToNextMinor(from: "0.57.3")),
    ],
    targets: [
        .target(name: "LaiaSkillsKit"),
        .executableTarget(
            name: "laiaskills",
            dependencies: [
                "LaiaSkillsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
            ]
        ),
        // Shared fixtures: scratch repos under tmp/, real git origins, a fake home.
        .target(name: "LaiaSkillsTestSupport", dependencies: ["LaiaSkillsKit"], path: "Tests/LaiaSkillsTestSupport"),
        .testTarget(name: "LaiaSkillsKitTests", dependencies: ["LaiaSkillsKit", "LaiaSkillsTestSupport"]),
        // Runs the built `laiaskills` binary end to end against fixture repos; depending on the
        // executable makes `swift test` build it first.
        .testTarget(name: "LaiaSkillsCLITests", dependencies: ["laiaskills", "LaiaSkillsKit", "LaiaSkillsTestSupport"]),
    ]
)
