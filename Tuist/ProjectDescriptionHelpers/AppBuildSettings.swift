import ProjectDescription

enum AppBuildSettings {
  static let settings: Settings = .settings(base: [
    "CURRENT_PROJECT_VERSION": .string(AppSettings.buildNumber),
    "GENERATE_INFOPLIST_FILE": true,
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": true,
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": true,
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
      "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": true,
    "MARKETING_VERSION": .string(AppSettings.marketingVersion),
    "SWIFT_APPROACHABLE_CONCURRENCY": true,
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_EMIT_LOC_STRINGS": true,
    "SWIFT_VERSION": "6.0",
  ])
}
