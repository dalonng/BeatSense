// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AAMStorages",
  platforms: [.iOS(.v26)],
  products: [
    .library(
      name: "AAMStorages",
      targets: ["AAMStorages"]
    ),
  ],
  dependencies: [
    .package(path: "../AANModels"),
  ],
  targets: [
    .target(name: "AAMStorages", dependencies: ["AANModels"]),
    .testTarget(name: "AAMStoragesTests", dependencies: ["AAMStorages", "AANModels"]),
  ]
)
