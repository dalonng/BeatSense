import ProjectDescription

public enum AppSettings {
  public static let projectName = "BeatSense"
  public static let teamId = Environment.developmentTeam.getString(default: "")

  static let bundleId = "com.mototo.beatsense"
  static let deploymentTarget = "27.0"
  static let marketingVersion = "1.0"
  static let buildNumber = "1"
}
