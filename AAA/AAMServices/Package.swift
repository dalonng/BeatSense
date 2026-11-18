// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AAMServices",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "AAMServices", targets: ["AAMServices"]),
  ],
  dependencies: [
    .package(path: "../AANModels"),
  ],
  targets: [
    .target(name: "AAMServices", dependencies: ["AANModels"], path: "Sources"),
    .testTarget(name: "AAMServicesTests", dependencies: ["AAMServices", "AANModels"]),
  ]
)
