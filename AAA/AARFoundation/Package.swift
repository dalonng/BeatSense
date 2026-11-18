// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AARFoundation",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "AARFoundation", targets: ["AARFoundation"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.15.1"),
  ],
  targets: [
    .target(
      name: "AARFoundation",
      dependencies: [.product(name: "Logging", package: "swift-log")],
      path: "Sources"
    ),
  ]
)
