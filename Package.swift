// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MovNetworkingTests",
    platforms: [.macOS(.v13)],
    products: [],
    targets: [
        .target(name: "MovNetworking", path: "Mov/Networking"),
        .testTarget(name: "MovNetworkingTests", dependencies: ["MovNetworking"], path: "Tests/MovNetworkingTests")
    ]
)
