import ProjectDescription

public enum AppPackages {
  private static let packageNames = [
    "AAAFeatures",
    "AACUseCases",
    "AAGComponents",
    "AAMServices",
    "AAMStorages",
    "AANModels",
    "AAODesignSystem",
    "AAPConfigurations",
    "AARFoundation",
  ]

  public static var projectPackages: [Package] {
    packageNames.map { .package(path: "AAA/\($0)") }
  }

  public static var targetDependencies: [TargetDependency] {
    packageNames.map { .package(product: $0) }
  }
}
