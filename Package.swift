// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GRPCClient",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "GRPCClient", targets: ["GRPCClient"]),
        .executable(name: "protoc-gen-grpc-client-swift", targets: ["protoc-gen-grpc-client-swift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.7.0")),
        .package(url: "https://github.com/grpc/grpc-swift.git", .exact("1.0.0-alpha.9"))
    ],
    targets: [
        .target(name: "GRPCClient", dependencies: ["GRPC"]),
        .target(name: "protoc-gen-grpc-client-swift", dependencies: ["SwiftProtobufPluginLibrary"])
    ]
)
