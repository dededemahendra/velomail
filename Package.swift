// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VeloCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "VeloCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
    ]
)
