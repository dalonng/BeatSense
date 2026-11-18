// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AANModels",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "AANModels", targets: ["AANModels"]),
  ],
  targets: [
    .target(name: "AANModels", path: "Sources"),
  ]
)
