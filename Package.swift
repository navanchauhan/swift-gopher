// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(Windows)
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
]
let serverDependencies: [Target.Dependency] = [
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
]
let clientDependencies: [Target.Dependency] = [
  "GopherHelpers",
]
#else
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
]
let serverDependencies: [Target.Dependency] = [
  .product(name: "NIO", package: "swift-nio"),
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  .product(name: "Logging", package: "swift-log"),
  "GopherHelpers",
]
let clientDependencies: [Target.Dependency] = [
  .product(name: "NIO", package: "swift-nio"),
  .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
  "GopherHelpers",
]
#endif

let package = Package(
  name: "SwiftGopher",
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
    .testTarget(
      name: "SwiftGopherClientTests",
      dependencies: ["SwiftGopherClient"]
    ),
    .testTarget(name: "SwiftGopherServerTests", dependencies: ["swift-gopher"])
  ]
)
