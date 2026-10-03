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
        .testTarget(name: "LaiaSkillsKitTests", dependencies: ["LaiaSkillsKit"]),
    ]
)
