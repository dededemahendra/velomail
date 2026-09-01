// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VeloMail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"]),
        .library(name: "VeloUI", targets: ["VeloUI"]),
        .executable(name: "VeloMail", targets: ["VeloMail"]),
        // Build-time tooling: draws the app icon. Deliberately not a
        // dependency of VeloMail, so none of it ships in the app.
        .executable(name: "velo-icon", targets: ["VeloIconTool"]),
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
        .target(name: "VeloIcon"),
        .executableTarget(name: "VeloIconTool", dependencies: ["VeloIcon"]),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
        .testTarget(name: "VeloUITests", dependencies: ["VeloUI"]),
        .testTarget(name: "VeloIconTests", dependencies: ["VeloIcon"]),
    ]
)
