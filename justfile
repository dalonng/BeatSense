app_name := "BeatSense"

default:
    @just --list

# Generate the Xcode workspace.
generate:
    tuist generate --no-open

# Generate and open the workspace in Xcode.
open: generate
    open "{{app_name}}.xcworkspace"

# Generate and open the workspace in Xcode Beta.
open-beta: generate
    open -a "/Applications/Xcode-beta.app" "{{app_name}}.xcworkspace"

# Format and build for iOS Simulator without signing.
build: format generate
    xcodebuild -workspace "{{app_name}}.xcworkspace" \
        -scheme "{{app_name}}" -configuration Debug \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath Derived/Build CODE_SIGNING_ALLOWED=NO build

# Check that Xcode can read the generated JSON project.
verify: generate
    test -f "{{app_name}}.xcodeproj/project.xcproj"
    xcodebuild -list -project "{{app_name}}.xcodeproj"

# Lint app, local packages, and Tuist configuration.
lint:
    swiftlint lint --config .swiftlint.yml --cache-path Derived/SwiftLint

# Format app, local packages, and Tuist configuration in place.
format:
    mkdir -p Derived
    swiftformat "{{app_name}}" AAA Project.swift Tuist.swift Tuist \
        --exclude '**/.build,**/.swiftpm' \
        --config .swiftformat --cache Derived/SwiftFormat.cache
