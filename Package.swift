// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StitchCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StitchCore", targets: ["StitchCore"])
    ],
    targets: [
        .target(name: "StitchCore"),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"]),
    ]
)
