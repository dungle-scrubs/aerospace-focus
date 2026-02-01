// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "aerospace-focus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.5.0")),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "aerospace-focus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
    ]
)
