import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
  name: AppSettings.projectName,
  options: .options(
    automaticSchemesOptions: .disabled,
    defaultKnownRegions: [
      "Base",
      "de",
      "en",
      "es",
      "fr",
      "ja",
      "zh-Hans",
    ]
  ),
  settings: .settings(base: [
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": true,
    "DEVELOPMENT_TEAM": .string(AppSettings.teamId),
    "ENABLE_USER_SCRIPT_SANDBOXING": true,
    "STRING_CATALOG_GENERATE_SYMBOLS": true,
  ]),
  targets: [AppTarget.make()],
  schemes: [AppSchemes.app],
  additionalFiles: [
    "Project.swift",
    "Tuist.swift",
    "Tuist/ProjectDescriptionHelpers/**",
    "Scripts/format-and-lint.sh",
    ".swiftformat",
    ".swiftlint.yml",
    "justfile",
    "mise.toml",
    "README.md",
  ]
)
