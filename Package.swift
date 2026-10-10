// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(Windows)
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1"),
]
let serverDependencies: [Target.Dependency] = [
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
  "GopherProxy",
]
let clientDependencies: [Target.Dependency] = [
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
]
#else
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1"),
  .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
]
let serverDependencies: [Target.Dependency] = [
  .product(name: "NIO", package: "swift-nio"),
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
  "GopherProxy",
]
let clientDependencies: [Target.Dependency] = [
  .product(name: "NIO", package: "swift-nio"),
  .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
]
#endif

let package = Package(
  name: "SwiftGopher",
  platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
  products: [
    .library(name: "SwiftGopherClient", targets: ["SwiftGopherClient"])
  ],
  dependencies: packageDependencies,
  targets: [
    .target(
      name: "GopherHelpers",
      dependencies: []
    ),
    .executableTarget(
      name: "swift-gopher",
      dependencies: serverDependencies
    ),
    .target(
      name: "SwiftGopherClient",
      dependencies: clientDependencies
    ),
    .target(
      name: "GopherProxy",
      dependencies: [
        "GopherHelpers",
        "SwiftGopherClient",
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .testTarget(
      name: "SwiftGopherClientTests",
      dependencies: ["SwiftGopherClient"]
    ),
    .testTarget(
      name: "GopherProxyTests",
      dependencies: ["GopherProxy"]
    ),
    .testTarget(
      name: "SwiftGopherServerTests",
      dependencies: [
        "swift-gopher",
        .product(name: "Logging", package: "swift-log"),
      ]
    )
  ]
)
