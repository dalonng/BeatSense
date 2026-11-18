app_name := "BeatSense"

default:
    @just --list

# Generate the Xcode workspace.
generate:
    tuist generate --no-open

# Generate and open the workspace in Xcode.
open: generate
    open "{{app_name}}.xcworkspace"

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

# Lint the Swift sources and Tuist configuration.
lint:
    swiftlint lint --config .swiftlint.yml --cache-path Derived/SwiftLint

# Format the Swift sources and Tuist configuration in place.
format:
    mkdir -p Derived
    swiftformat "{{app_name}}" Project.swift Tuist.swift Tuist \
        --config .swiftformat --cache Derived/SwiftFormat.cache
