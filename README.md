# BeatSense
Turn Apple Health heart rate, HRV, and sleep data into digestible recovery and cardiovascular insights. Built with SwiftUI &amp; HealthKit.

## iOS development

Use Xcode 27 and mise for local development. The app targets iOS 27 or later and currently opens to a blank SwiftUI screen. `mise.toml` pins Just, Tuist, SwiftLint, and SwiftFormat.

Run these commands from the repository root.

```sh
./Scripts/setup.sh        # Install the pinned tools and generate the workspace
mise exec -- just open    # Generate the workspace and open it in Xcode
mise exec -- just build   # Format Swift files and build for iOS Simulator
mise exec -- just verify  # Check the generated project file
mise exec -- just lint    # Check Swift code for lint violations
mise exec -- just format  # Format Swift files in place
```

With mise active in your shell, run recipes directly with `just`.

`Project.swift` assembles the Tuist project from the app settings, target, build settings, and shared scheme in `Tuist/ProjectDescriptionHelpers/`.

Tuist generates the Xcode JSON project configuration at `BeatSense.xcodeproj/project.xcproj`.

The sandboxed `Check Swift Formatting and Lint` build phase runs SwiftFormat and SwiftLint in read-only mode before compiling the app. Formatting and lint violations fail the build. Run `mise exec -- just format` to apply formatting before building in Xcode.

### Local signing

Set your Apple Developer Team ID in the Git-ignored `.env.local` file at the repository root.

```dotenv
TUIST_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

Run `mise exec -- just generate` after changing the Team ID. Simulator builds can run without `.env.local`.
