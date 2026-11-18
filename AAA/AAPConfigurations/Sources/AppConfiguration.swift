//
//  AppConfiguration.swift
//
//
//  Created by 大桥 on 2024/8/30.
//

import Foundation
import StoreKit

public enum AppConfiguration {
  // MARK: - App Store Configuration

  /// Optional App Store Connect ID supplied through the app's Info.plist.
  public static var appleID: String? {
    configuredString("APP_STORE_APPLE_ID")
  }

  /// App Store URL for sharing and reviews
  public static var appStoreURL: URL? {
    guard let appleID else {
      return nil
    }
    return URL(string: "https://apps.apple.com/app/id\(appleID)")
  }

  /// Optional public invitation code supplied through the app's Info.plist.
  public static var testFlightCode: String? {
    configuredString("TESTFLIGHT_PUBLIC_LINK_CODE")
  }

  /// Share URL - uses TestFlight link if available and in development/TestFlight, otherwise App
  /// Store
  public static var shareURL: URL? {
    get async throws {
      if let code = testFlightCode, try await distribution != .appStore {
        return URL(string: "https://testflight.apple.com/join/\(code)")
      }
      return appStoreURL
    }
  }

  // MARK: - Distribution & Environment

  public static var distribution: Distribution {
    get async throws {
      try await Distribution.current
    }
  }

  public static var configuration: Configuration {
    #if DEBUG
      Configuration.debug
    #else
      Configuration.release
    #endif
  }

  public static var environment: AppEnvironment {
    #if DEVELOPMENT
      return AppEnvironment.development
    #endif
    return AppEnvironment.production
  }

  /// A backend is available only when explicitly configured by the host app.
  public static var baseURL: String? {
    configuredString("BASE_URL")
  }

  /// Use the host app's identity, including when running an alternate app variant.
  public static var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
  }

  public static var displayName: String {
    configuredString("CFBundleDisplayName")
      ?? configuredString("CFBundleName")
      ?? ProcessInfo.processInfo.processName
  }

  private static func configuredString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  public enum Configuration {
    case debug
    case release
  }

  public enum AppEnvironment: String, CaseIterable {
    case development = "Development"
    case production = "Production"
  }

  public enum Distribution: String, Sendable {
    case appStore = "AppStore"
    case testFlight = "TestFlight"
    case development = "Development"

    static var current: Distribution {
      get async throws {
        #if DEBUG
          .development
        #else
          switch try await AppTransaction.shared {
          case let .verified(transaction):
            switch transaction.environment {
            case .sandbox:
              .testFlight
            case .xcode:
              .development
            default:
              .appStore
            }
          case let .unverified(_, error):
            throw error
          }
        #endif
      }
    }
  }
}
