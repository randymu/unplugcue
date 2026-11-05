// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaCieSafeOff",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LaCieSafeOff", targets: ["LaCieSafeOff"])
    ],
    targets: [
        .executableTarget(
            name: "LaCieSafeOff",
            path: "Sources/LaCieSafeOff"
        ),
        .testTarget(name: "LaCieSafeOffTests", dependencies: ["LaCieSafeOff"])
    ]
)
