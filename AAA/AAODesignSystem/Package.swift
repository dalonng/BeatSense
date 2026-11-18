// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "AAODesignSystem",
  platforms: [.iOS(.v26)],
  products: [
    .library(
      name: "AAODesignSystem",
      targets: ["AAODesignSystem"]
    ),
  ],
  targets: [
    .target(name: "AAODesignSystem", path: "Sources"),
  ]
)
