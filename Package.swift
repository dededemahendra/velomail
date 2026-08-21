// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VeloMail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"]),
        .library(name: "VeloUI", targets: ["VeloUI"]),
        .executable(name: "VeloMail", targets: ["VeloMail"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "VeloCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "VeloUI", dependencies: ["VeloCore"]),
        .executableTarget(name: "VeloMail", dependencies: ["VeloUI"]),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
        .testTarget(name: "VeloUITests", dependencies: ["VeloUI"]),
    ]
)
