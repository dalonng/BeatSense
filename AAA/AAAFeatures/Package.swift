// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "AAAFeatures",
  defaultLocalization: "en",
  platforms: [.iOS(.v27)],
  products: [
    .library(name: "AAAFeatures", targets: ["AAAFeatures"]),
  ],
  dependencies: [
    .package(path: "../AACUseCases"),
    .package(path: "../AAGComponents"),
    .package(path: "../AAMServices"),
    .package(path: "../AAMStorages"),
    .package(path: "../AANModels"),
    .package(path: "../AAODesignSystem"),
    .package(path: "../AARFoundation"),
  ],
  targets: [
    .target(
      name: "AAAFeatures",
      dependencies: [
        "AACUseCases",
        "AAGComponents",
        "AAMServices",
        "AAMStorages",
        "AANModels",
        "AAODesignSystem",
        "AARFoundation",
      ],
      path: ".",
      exclude: ["Tests"],
      sources: ["Sources"],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "AAAFeaturesTests",
      dependencies: ["AAAFeatures", "AACUseCases", "AAMServices", "AAMStorages", "AANModels"]
    ),
  ]
)
