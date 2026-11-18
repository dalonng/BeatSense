import ProjectDescription

public enum AppSchemes {
  private static let target = TargetReference.target(AppSettings.projectName)

  public static let app = Scheme.scheme(
    name: AppSettings.projectName,
    shared: true,
    buildAction: .buildAction(targets: [target]),
    runAction: .runAction(configuration: .debug, executable: .executable(target))
  )
}
