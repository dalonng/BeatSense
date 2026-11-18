// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AACUseCases",
  platforms: [.iOS(.v27)],
  products: [
    .library(name: "AACUseCases", targets: ["AACUseCases"]),
  ],
  dependencies: [
    .package(path: "../AAMServices"),
    .package(path: "../AAMStorages"),
    .package(path: "../AANModels"),
  ],
  targets: [
    .target(name: "AACUseCases", dependencies: ["AAMServices", "AAMStorages", "AANModels"], path: "Sources"),
  ]
)
