import Foundation

public enum DependencyError: Error, Equatable, CustomStringConvertible {
  case notInstalled
  case invalidInstallation(String)
  case versionCheckFailed(String)
  case unsupportedVersion(component: String, expected: String, actual: String)

  public var description: String {
    switch self {
    case .notInstalled:
      "pinentry-companion and pam-companion were not found in the same Homebrew prefix"
    case .invalidInstallation(let component):
      "\(component) does not resolve to an executable inside its Homebrew Cellar"
    case .versionCheckFailed(let component):
      "\(component) did not return its version successfully"
    case .unsupportedVersion(let component, let expected, let actual):
      "unsupported \(component) version \(actual); AuthCompanion requires \(expected)"
    }
  }
}

public protocol ComponentLocating {
  func locate() throws -> ComponentPaths
}

public struct HomebrewComponentLocator: ComponentLocating {
  private let prefixes: [String]
  private let fileManager: FileManager

  public init() {
    prefixes = Self.defaultPrefixes
    fileManager = .default
  }

  public init(prefixes: [String]) {
    self.prefixes = prefixes
    fileManager = .default
  }

  public func locate() throws -> ComponentPaths {
    for prefix in prefixes {
      do {
        return ComponentPaths(
          pinentryExecutable: try executable(
            formula: "pinentry-companion",
            prefix: prefix
          ),
          pamExecutable: try executable(
            formula: "pam-companion",
            prefix: prefix
          ),
          sudoExecutable: "/usr/bin/sudo"
        )
      } catch LocatorError.missing {
        continue
      } catch LocatorError.invalid(let component) {
        throw DependencyError.invalidInstallation(component)
      }
    }
    throw DependencyError.notInstalled
  }

  private func executable(formula: String, prefix: String) throws -> String {
    let root = URL(fileURLWithPath: prefix, isDirectory: true).standardizedFileURL
    let optExecutable =
      root
      .appendingPathComponent("opt/\(formula)/bin/\(formula)")
    guard fileManager.fileExists(atPath: optExecutable.path) else {
      throw LocatorError.missing
    }
    let resolved = optExecutable.resolvingSymlinksInPath().standardizedFileURL
    let cellar =
      root
      .appendingPathComponent("Cellar/\(formula)", isDirectory: true)
      .standardizedFileURL.path + "/"
    guard resolved.path.hasPrefix(cellar), fileManager.isExecutableFile(atPath: resolved.path)
    else {
      throw LocatorError.invalid(formula)
    }
    return resolved.path
  }

  private enum LocatorError: Error {
    case missing
    case invalid(String)
  }

  private static var defaultPrefixes: [String] {
    #if arch(arm64)
      ["/opt/homebrew", "/usr/local"]
    #else
      ["/usr/local", "/opt/homebrew"]
    #endif
  }
}

public enum ComponentVersionVerifier {
  public static func verify(paths: ComponentPaths, runner: any ToolRunning) throws {
    try verify(
      component: "pinentry-companion",
      expectedVersion: SupportedComponentVersions.pinentryCompanion,
      executable: paths.pinentryExecutable,
      runner: runner
    )
    try verify(
      component: "pam-companion",
      expectedVersion: SupportedComponentVersions.pamCompanion,
      executable: paths.pamExecutable,
      runner: runner
    )
  }

  private static func verify(
    component: String,
    expectedVersion: String,
    executable: String,
    runner: any ToolRunning
  ) throws {
    let result = try runner.run(ToolInvocation(executable: executable, arguments: ["--version"]))
    guard result.exitStatus == 0,
      let output = String(data: result.stdout, encoding: .utf8)
    else {
      throw DependencyError.versionCheckFailed(component)
    }
    let actual = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let expected = "\(component) \(expectedVersion)"
    guard actual == expected else {
      throw DependencyError.unsupportedVersion(
        component: component,
        expected: expectedVersion,
        actual: actual
      )
    }
  }
}
