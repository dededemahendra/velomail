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
        // GRDB is explicit rather than transitive: VeloUI retains the
        // AnyDatabaseCancellable that MailStore's observation returns.
        .target(name: "VeloUI", dependencies: ["VeloCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "VeloMail", dependencies: ["VeloUI"]),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
        .testTarget(name: "VeloUITests", dependencies: ["VeloUI"]),
    ]
)
