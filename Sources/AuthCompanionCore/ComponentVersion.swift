public enum AuthCompanionVersion {
  public static let current = "0.2.0"
}

public enum SupportedComponentVersions {
  public static let pinentryCompanion = ["0.2.0", "0.2.1"]
  public static let pamCompanion = ["0.1.1", "0.2.0"]
}

public struct ComponentVersions: Equatable, Sendable {
  public let pinentryCompanion: String
  public let pamCompanion: String

  public init(pinentryCompanion: String, pamCompanion: String) {
    self.pinentryCompanion = pinentryCompanion
    self.pamCompanion = pamCompanion
  }
}
