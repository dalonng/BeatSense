# BeatSense
Turn Apple Health heart rate, HRV, and sleep data into digestible recovery and cardiovascular insights. Built with SwiftUI &amp; HealthKit.

## iOS development

Use Xcode 27 and mise for local development. The app targets iOS 27 or later. Today shows resting heart rate and heart rate variability (SDNN) together, with separate readings, timestamps, and personal baseline comparisons. Blood oxygen and respiratory rate show the latest visible readings from the past seven days. The heart rate card summarizes the same interval with the latest value, mean, maximum, minimum, and the share of measurements in each BPM range. Tap any of these five metrics to chart its readings for the current local calendar day. Resting heart rate and HRV open separately from their shared card. The time picker defaults to D (the full day). `1 H` and `12H` show a window ending at the end of the latest reading’s hour today, or the current hour if there are no readings today. Early in the day the window starts at midnight and extends forward to its selected length. Each window reads verified local measurements. Windows with more than 193 measurements display the low and high readings from each of 96 time intervals and the latest reading. An empty window keeps its time axis. Longevity and Health Insights are placeholders. `mise.toml` pins Just, Tuist, SwiftLint, and SwiftFormat.

Today also shows the main sleep session ending on the current local day. Its two badges show time asleep and the first and last recorded sleep times. The app reads sleep from HealthKit on refresh and keeps the result in memory. Gaps of up to 90 minutes can belong to the same session. If several sessions end today, the one with the most time asleep is shown, with the later session winning a tie.

The sleep card shows recorded time in deep, core, and REM sleep, plus recorded time awake between the first and last sleep intervals. Overlapping records count once. An explicit awake interval takes precedence and is excluded from total sleep. A specific sleep stage takes precedence over a generic asleep record. Time with only generic sleep records or with conflicting specific stages contributes to unclassified sleep. Gaps without samples contribute to neither sleep nor awake time.

Trends charts the five quantitative measurements over the last 7 or 30 local calendar days, including today. The range picker defaults to 30 days. Each day shows the mean heart rate, the latest resting heart rate, blood oxygen and respiratory rate, and the median HRV from readings comparable to that day's latest usable sample. Each HRV point can therefore represent a different two-hour time block. Days without visible readings appear as gaps. Both ranges use the same set of verified local HealthKit results, so switching ranges applies immediately. Trends respects the retention setting.

Each personal baseline uses the median of daily values from the previous 28 complete local days. The 10th and 90th percentiles give the usual range, with at least 21 valid days required. Resting heart rate uses the latest estimate each day from the same source and device when available.

For HRV, BeatSense selects the two-hour local time block with readings on the most distinct historical days. Eligible readings match the newest usable sample's source and device, with recording durations within 15 seconds of its duration. A zero duration matches only another zero duration. Ties go to the earlier time block. BeatSense keeps the selected block and its reference duration while the source, device and time zone match and at least 21 historical days still qualify. The baseline gives each day's median equal weight. Today displays the latest HRV reading and its timestamp separately from today's reference-block median. Only that median is compared with the baseline. If today has no comparable reading, the baseline remains available.

When Today's personal baseline is available, Trends overlays it on the resting heart rate and HRV charts. A shaded band marks the current P10–P90 usual range, and a dashed line marks the current median. On the HRV chart, the band and line describe the selected reference block. Both chart ranges use the same baseline.

By default, BeatSense reads the past 90 days of the five quantitative HealthKit measurements and stores them on this device. The Today gear menu sets a custom retention period, which takes precedence over the default. Increasing the window imports earlier visible samples. Decreasing it removes older local measurements. Each current personal baseline is saved with P10, P50, P90 and its calculation context, including when today has no reading.

The app verifies HealthKit visibility on activation and applies additions and deletions while in the foreground, including while another tab is open. Today updates each card independently. Within the same foreground session, returning to Trends shows its verified charts immediately. New samples refresh the charts in place. Returning from the background revalidates the readings before displaying them again.

Run these commands from the repository root.

```sh
./Scripts/setup.sh        # Install the pinned tools and generate the workspace
mise exec -- just open    # Generate the workspace and open it in Xcode
mise exec -- just open-beta # Generate the workspace and open it in Xcode Beta
mise exec -- just build   # Format Swift files and build for iOS Simulator
mise exec -- just verify  # Check the generated project file
mise exec -- just lint    # Check Swift code for lint violations
mise exec -- just format  # Format Swift files in place
```

With mise active in your shell, run recipes directly with `just`.

`Project.swift` assembles the Tuist project from the app settings, target, build settings, and shared scheme in `Tuist/ProjectDescriptionHelpers/`.

Tuist generates the Xcode JSON project configuration at `BeatSense.xcodeproj/project.xcproj`.

### Local Swift packages

`AAA/` contains local Swift packages migrated from Vocsy. `AppPackages.swift` registers their products with the app; each package maintains its own source, resource, dependency, and test declarations.

The package name prefixes define the architecture order below.

- `AAAFeatures` owns all top-level feature UI, including root navigation, feature screens, screen-level view models, and localized interface copy.
- `AACUseCases` owns business use cases. `SynchronizeHealthHistory` coordinates the history mirror and projections. `RefreshTodayHealth` handles explicit authorization and sends individual metric updates to Today.
- `AAGComponents` owns business view components that have no view model dependency, including Today's metric views and heart rate charts. Component-specific translations are bundled with this package.
- `AAMServices` owns the read-only `AppleHealthClient` in `Sources/AppleHealth/`. The app entry point shares one instance across windows. It reads anchored pages and expands quantity series into individual measurements. See the [Apple Health service boundary](docs/adr/0001-apple-health-service-boundary.md).
- `AAMStorages` stores individual samples, sync positions, and current personal baselines in a protected, on-device SwiftData database excluded from backup. See the [health history storage decision](docs/adr/0003-health-history-and-personal-baselines.md).
- `AANModels` defines shared health value types. `AAMServices` converts HealthKit samples into those types at the service boundary.
- `AAODesignSystem` provides design tokens.
- `AAPConfigurations` provides app configuration.
- `AARFoundation` provides SwiftLog backends for Unified Logging and stdout, plus signposts for events and timed operations.

The project excludes the legacy recording, playback, and translation services, ONNX binaries, SenseVoice transcription, Vocsy screens, and conversation persistence.

The packages require Swift tools 6.4. The application modules are local Swift packages. `AARFoundation` pins Apple's `swift-log` dependency at the version recorded in `.package.resolved`.

`BeatSenseApp.init()` calls `AAAFeatures.AppBootstrapper.shared.configureCoreServices()` before creating app dependencies. The bootstrapper skips process-wide SwiftLog configuration when `XCODE_RUNNING_FOR_PREVIEWS=1` or `XCTestConfigurationFilePath` is set. Debug uses a `.debug` threshold and sends events to both Unified Logging and the console. Release uses an `.info` threshold and sends events to Unified Logging only. Unified Logging marks messages and metadata as private, while console output writes them to stdout in cleartext. The first bootstrap configuration applies for the process lifetime. SwiftLog producers can use `AppLogging.logger(category:)`, and the logger's signpost helpers use the same subsystem and category. Keep health data and personal identifiers out of all log and signpost payloads.

`AAAFeatures.AppDelegate` forwards UIKit launch options from `didFinishLaunchingWithOptions` to `AppBootstrapper` for integrations that require this callback.

Console output uses UTC ISO 8601 timestamps with fractional seconds. For both backends, per-event metadata overrides logger metadata, which overrides values from the metadata provider.

Set `AppLogging.Configuration.metadataProvider` to supply dynamic metadata at bootstrap. Each backend evaluates the effective provider when it emits an event. A SwiftLog logger can supply its own provider to override the process default.

Both signpost interval helpers propagate the operation's concrete error type. The async helper runs the operation on the caller's actor and supports non-`Sendable` results.

`just format` and `just lint` cover app, `AAA/`, and Tuist files. The app's build-phase checks cover app and Tuist files.

The sandboxed `Check Swift Formatting and Lint` build phase runs SwiftFormat and SwiftLint in read-only mode before compiling the app. Formatting and lint violations fail the build. Run `mise exec -- just format` to apply formatting before building in Xcode.

Run the `AAMServices`, `AAMStorages`, and `AAAFeatures` package schemes on an iOS simulator to execute their Swift Testing suites. When testing `AAAFeatures` directly with `xcodebuild`, pass `STRING_CATALOG_GENERATE_SYMBOLS=YES` to generate its localized Swift symbols.

### Local signing

Set your Apple Developer Team ID in the Git-ignored `.env.local` file at the repository root.

```dotenv
TUIST_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

Run `mise exec -- just generate` after changing the Team ID. Simulator builds can run without `.env.local`.

### Verify Apple Health on a device

Use a provisioning profile for the BeatSense App ID with HealthKit enabled. On a fresh installation, open Today and tap **Connect Apple Health**. Verify that the system sheet offers read access to the five quantitative measurements and Sleep together.

On an installation already connected to the five measurements, verify that Today and Trends continue showing the existing readings after the upgrade. Open the sleep card’s connection action and verify that the sheet requests only Sleep. Leaving Sleep off should keep all five measurements and their history available.

For each quantitative type with a sample dated within the past seven days, verify that Today shows the latest value and its timestamp. After revoking access to one type in Health, return to Today and verify its empty state and that the other measurements still appear. Restore access and verify the history backfills. Change the retention days and verify the local range expands or expires accordingly. Today uses the last seven days for its recent readings, subject to the retention window.

Let a supported sample sync from a paired Apple Watch or another Health data source. Verify that Today updates without tapping Refresh, including after switching away from Today and back. Delete a source sample and verify that Today shows the latest remaining reading or the empty state. Include a condensed heart-rate series crossing the retention boundary and verify that its individual values are retained when in range. Verify lock and unlock recovery on a physical device.

With a recorded night ending today, compare the sleep card’s deep, core, REM, and awake durations with the intervals recorded for that session in Health. On a night with only a total sleep record, verify that Today shows the duration and identifies the missing stage detail. Verify that overlapping stages count once, awake intervals are excluded, and deleting the night or withdrawing Sleep access clears the card.

Open each quantitative metric on Today. Compare the chart with the measurements recorded since local midnight, including single readings and days with no samples. With the detail open, delete an earlier reading from Health and return to BeatSense. The chart should reflect the deletion even when the latest reading on the card stays the same.

With HRV readings in the same two-hour block on at least 21 of the previous 28 days, verify that a newer reading in another block updates the latest value and timestamp while the baseline stays available. Check today's reference-block median against today's comparable readings. On a day with only out-of-block readings, verify that Today still shows the latest reading and says there is no comparable reading today.

In Trends, verify that the default 30-day view covers today and the preceding 29 local dates. Select 7 Days and verify that all charts switch to today and the preceding six local dates. Select a date with multiple measurements and verify each daily value. Check that days without samples appear as gaps, and that removing a sample, revoking read access or shortening retention updates the affected charts. With at least 21 comparable days, check that the resting heart rate and HRV baseline bands and medians match for both ranges. Shorten retention below 21 days and verify that the charts indicate the baseline is still building.

For a simulator smoke test, run the shared `BeatSense` scheme in Xcode so the app contains the simulated HealthKit entitlement.
