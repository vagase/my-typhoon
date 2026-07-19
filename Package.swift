// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TyphoonBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TyphoonBar", targets: ["TyphoonBar"])
    ],
    targets: [
        .executableTarget(
            name: "TyphoonBar",
            path: "Sources/TyphoonBar"
        )
    ]
)
