// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AAPConfigurations",
  platforms: [.iOS(.v26)],
  products: [
    .library(
      name: "AAPConfigurations",
      targets: ["AAPConfigurations"]
    ),
  ],
  targets: [
    .target(
      name: "AAPConfigurations"
    ),
  ]
)
