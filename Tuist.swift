import ProjectDescription

let tuist = Tuist(
  project: .tuist(
    compatibleXcodeVersions: [.upToNextMajor("27.0.0")],
    generationOptions: .options(projectFormat: .xcproj)
  )
)
