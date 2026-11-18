import ProjectDescription

public enum AppTarget {
  private static let healthShareUsageDescription =
    "BeatSense reads your heart rate, resting heart rate, blood oxygen, respiratory rate, and heart rate variability "
      + "from Apple Health to show recent measurements and personal baselines. This history is saved on your device. "
      + "BeatSense also reads sleep data to show your sleep duration, sleep period, and recorded stages in Today."

  public static func make() -> Target {
    .target(
      name: AppSettings.projectName,
      destinations: [.iPhone, .iPad],
      product: .app,
      bundleId: AppSettings.bundleId,
      deploymentTargets: .iOS(AppSettings.deploymentTarget),
      infoPlist: .extendingDefault(with: [
        "CFBundleLocalizations": .array(AppSettings.localizations.map { .string($0) }),
        "NSHealthShareUsageDescription": .string(healthShareUsageDescription),
        "UILaunchScreen": .dictionary([:]),
      ]),
      sources: ["BeatSense/Sources/**"],
      resources: ["BeatSense/Resources/**"],
      entitlements: .dictionary([
        "com.apple.developer.healthkit": true,
      ]),
      scripts: [
        .pre(
          path: "Scripts/format-and-lint.sh",
          name: "Check Swift Formatting and Lint",
          inputPaths: [
            "Scripts/format-and-lint.sh",
            ".swiftformat",
            ".swiftlint.yml",
            "mise.toml",
            "BeatSense/**/*.swift",
            "Project.swift",
            "Tuist.swift",
            "Tuist/**/*.swift",
          ],
          basedOnDependencyAnalysis: false
        ),
      ],
      dependencies: AppPackages.targetDependencies,
      settings: AppBuildSettings.settings
    )
  }
}
