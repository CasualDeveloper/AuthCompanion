import Foundation
import XCTest

@testable import AuthCompanionCore

final class DependencyResolutionTests: XCTestCase {
  private var fixtureURL: URL!

  override func setUpWithError() throws {
    fixtureURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("authcompanion-dependencies-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: fixtureURL)
  }

  func testResolvesOnlyExecutablesInsideFormulaCellars() throws {
    _ = try installFormula(name: "pinentry-companion", version: "0.2.0")
    _ = try installFormula(name: "pam-companion", version: "0.1.1")
    let locator = HomebrewComponentLocator(prefixes: [fixtureURL.path])

    let paths = try locator.locate()

    XCTAssertEqual(
      paths.pinentryExecutable,
      fixtureURL.appendingPathComponent("opt/pinentry-companion/bin/pinentry-companion").path
    )
    XCTAssertEqual(
      paths.pamExecutable,
      fixtureURL.appendingPathComponent("opt/pam-companion/bin/pam-companion").path
    )
    XCTAssertEqual(paths.sudoExecutable, "/usr/bin/sudo")
  }

  func testRejectsOptLinkThatEscapesFormulaCellar() throws {
    _ = try installFormula(name: "pam-companion", version: "0.1.1")
    let executable = fixtureURL.appendingPathComponent("outside/pinentry-companion")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: executable.path, contents: Data())
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let optDirectory = fixtureURL.appendingPathComponent("opt/pinentry-companion/bin")
    try FileManager.default.createDirectory(at: optDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: optDirectory.appendingPathComponent("pinentry-companion"),
      withDestinationURL: executable
    )

    XCTAssertThrowsError(
      try HomebrewComponentLocator(prefixes: [fixtureURL.path]).locate()
    ) { error in
      XCTAssertEqual(error as? DependencyError, .invalidInstallation("pinentry-companion"))
    }
  }

  func testVerifierRequiresExactReleasedVersions() throws {
    let runner = DependencyStubRunner(results: [
      ToolResult(exitStatus: 0, stdout: Data("pinentry-companion 0.2.0\n".utf8), stderr: Data()),
      ToolResult(exitStatus: 0, stdout: Data("pam-companion 0.1.1\n".utf8), stderr: Data()),
    ])
    let paths = ComponentPaths(
      pinentryExecutable: "/fixed/pinentry-companion",
      pamExecutable: "/fixed/pam-companion",
      sudoExecutable: "/usr/bin/sudo"
    )

    try ComponentVersionVerifier.verify(paths: paths, runner: runner)

    XCTAssertEqual(
      runner.invocations,
      [
        ToolInvocation(executable: paths.pinentryExecutable, arguments: ["--version"]),
        ToolInvocation(executable: paths.pamExecutable, arguments: ["--version"]),
      ])
  }

  func testVerifierRejectsAnUnsupportedVersion() {
    let runner = DependencyStubRunner(results: [
      ToolResult(exitStatus: 0, stdout: Data("pinentry-companion 0.3.0\n".utf8), stderr: Data())
    ])
    let paths = ComponentPaths(
      pinentryExecutable: "/fixed/pinentry-companion",
      pamExecutable: "/fixed/pam-companion",
      sudoExecutable: "/usr/bin/sudo"
    )

    XCTAssertThrowsError(try ComponentVersionVerifier.verify(paths: paths, runner: runner)) {
      error in
      XCTAssertEqual(
        error as? DependencyError,
        .unsupportedVersion(
          component: "pinentry-companion",
          expected: "0.2.0 or 0.2.1",
          actual: "pinentry-companion 0.3.0"
        )
      )
    }
  }

  func testVerifierAcceptsEverySupportedRollingUpgradePair() {
    let paths = ComponentPaths(
      pinentryExecutable: "/fixed/pinentry-companion",
      pamExecutable: "/fixed/pam-companion",
      sudoExecutable: "/usr/bin/sudo"
    )
    for pinentry in ["0.2.0", "0.2.1"] {
      for pam in ["0.1.1", "0.2.0"] {
        let runner = DependencyStubRunner(results: [
          ToolResult(
            exitStatus: 0, stdout: Data("pinentry-companion \(pinentry)\n".utf8), stderr: Data()),
          ToolResult(
            exitStatus: 0, stdout: Data("pam-companion \(pam)\n".utf8), stderr: Data()),
        ])
        XCTAssertNoThrow(
          try ComponentVersionVerifier.verify(paths: paths, runner: runner),
          "pinentry \(pinentry), PAM \(pam)"
        )
      }
    }
  }

  private func installFormula(name: String, version: String) throws -> URL {
    let versionDirectory = fixtureURL.appendingPathComponent("Cellar/\(name)/\(version)")
    let executable = versionDirectory.appendingPathComponent("bin/\(name)")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: executable.path, contents: Data())
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let opt = fixtureURL.appendingPathComponent("opt/\(name)")
    try FileManager.default.createDirectory(
      at: opt.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: opt, withDestinationURL: versionDirectory)
    return executable
  }
}

private final class DependencyStubRunner: ToolRunning {
  private var results: [ToolResult]
  private(set) var invocations: [ToolInvocation] = []

  init(results: [ToolResult]) {
    self.results = results
  }

  func run(_ invocation: ToolInvocation) throws -> ToolResult {
    invocations.append(invocation)
    guard !results.isEmpty else { throw DependencyError.notInstalled }
    return results.removeFirst()
  }
}
