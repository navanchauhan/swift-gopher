// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swiftGopher",
  products: [
    .library(
        name: "swiftGopher",
        targets: ["swiftGopherClient"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-nio",
      from: "2.0.0"
    ),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "swift-gopher",
      dependencies: [
        .product(
          name: "NIO",
          package: "swift-nio"
        ),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .target(
        name: "swiftGopherClient",
        dependencies: [
            .product(name: "NIO", package: "swift-nio")
        ]
    ),
    .testTarget(
        name: "swiftGopherClientTests",
        dependencies: ["swiftGopherClient"]
    )
  ]
)
