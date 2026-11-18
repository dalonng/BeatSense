import ProjectDescription

public enum AppTarget {
  public static func make() -> Target {
    .target(
      name: AppSettings.projectName,
      destinations: [.iPhone, .iPad],
      product: .app,
      bundleId: AppSettings.bundleId,
      deploymentTargets: .iOS(AppSettings.deploymentTarget),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": .dictionary([:])]),
      sources: ["BeatSense/Sources/**"],
      resources: ["BeatSense/Resources/**"],
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
      settings: AppBuildSettings.settings
    )
  }
}
