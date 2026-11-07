// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputRedirection", platforms: [.macOS(.v13)],
    products: [.executable(name: "InputRedirection", targets: ["InputRedirection"])],
    targets: [
        .target(name: "InputCore"),
        .executableTarget(name: "InputRedirection", dependencies: ["InputCore"]),
        .testTarget(name: "InputCoreTests", dependencies: ["InputCore"]),
        .testTarget(name: "ClientTests", dependencies: ["InputRedirection"]),
    ])
