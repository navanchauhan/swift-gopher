// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftGopher",
  products: [
    .library(name: "SwiftGopherClient", targets: ["SwiftGopherClient"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),

  ],
  targets: [
    .target(
      name: "GopherHelpers",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio")
      ]
    ),
    .executableTarget(
      name: "swift-gopher",
      dependencies: [
        .product(
          name: "NIO",
          package: "swift-nio"
        ),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        "GopherHelpers",
      ]
    ),
    .target(
      name: "SwiftGopherClient",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        "GopherHelpers",
      ]
    ),
    .testTarget(
      name: "SwiftGopherClientTests",
      dependencies: ["SwiftGopherClient"]
    ),
    .testTarget(name: "SwiftGopherServerTests", dependencies: ["swift-gopher"])
  ]
)
