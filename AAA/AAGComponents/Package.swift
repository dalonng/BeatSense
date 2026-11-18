// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AAGComponents",
  defaultLocalization: "en",
  platforms: [.iOS(.v27)],
  products: [
    .library(name: "AAGComponents", targets: ["AAGComponents"]),
  ],
  dependencies: [
    .package(path: "../AANModels"),
    .package(path: "../AAODesignSystem"),
  ],
  targets: [
    .target(
      name: "AAGComponents",
      dependencies: ["AANModels", "AAODesignSystem"],
      path: ".",
      sources: ["Sources"],
      resources: [.process("Resources")]
    ),
  ]
)
