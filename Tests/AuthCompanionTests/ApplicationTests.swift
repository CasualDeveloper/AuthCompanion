import Foundation
import XCTest

@testable import AuthCompanionCore

final class ApplicationTests: XCTestCase {
  func testHelpAndVersionDoNotResolveDependenciesEvenAsRoot() {
    let locator = ApplicationLocator(error: DependencyError.notInstalled)
    let runner = ApplicationRunner(results: [])
    let application = makeApplication(effectiveUserID: 0, locator: locator, runner: runner)

    let help = application.run(["authcompanion", "--help"])
    let version = application.run(["authcompanion", "--version"])

    XCTAssertEqual(help.exitStatus, 0)
    XCTAssertTrue(help.stdout.contains("Usage:"))
    XCTAssertEqual(version.stdout, "authcompanion 0.1.0\n")
    XCTAssertEqual(locator.locateCount, 0)
    XCTAssertTrue(runner.invocations.isEmpty)
  }

  func testOperationalCommandRejectsRootBeforeDependencyResolution() throws {
    let locator = ApplicationLocator(error: DependencyError.notInstalled)
    let runner = ApplicationRunner(results: [])
    let application = makeApplication(effectiveUserID: 0, locator: locator, runner: runner)

    let output = application.run(["authcompanion", "status", "--format", "json"])
    let envelope = try JSONDecoder().decode(
      AuthEnvelope<FailureState>.self, from: Data(output.stdout.utf8))

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertEqual(envelope.operation, "status")
    XCTAssertEqual(envelope.diagnostics.first?.code, "invocation.rootForbidden")
    XCTAssertEqual(locator.locateCount, 0)
    XCTAssertTrue(runner.invocations.isEmpty)
  }

  func testJSONStatusVerifiesDependenciesThenUsesOnlyPassiveComponentEndpoint() throws {
    let paths = ComponentPaths(
      pinentryExecutable: "/fixed/pinentry-companion",
      pamExecutable: "/fixed/pam-companion",
      sudoExecutable: "/usr/bin/sudo"
    )
    let locator = ApplicationLocator(paths: paths)
    let runner = ApplicationRunner(results: [
      ToolResult(
        exitStatus: 0,
        stdout: Data("pinentry-companion 0.2.0\n".utf8),
        stderr: Data()
      ),
      ToolResult(
        exitStatus: 0,
        stdout: Data("pam-companion 0.1.0\n".utf8),
        stderr: Data()
      ),
      ToolResult(exitStatus: 0, stdout: pinentryStatusJSON(), stderr: Data()),
    ])
    let application = makeApplication(effectiveUserID: 501, locator: locator, runner: runner)

    let output = application.run(["authcompanion", "status", "--format", "json"])
    let envelope = try JSONDecoder().decode(
      AuthEnvelope<StatusState>.self, from: Data(output.stdout.utf8))

    XCTAssertEqual(output.exitStatus, 0)
    XCTAssertTrue(output.stderr.isEmpty)
    XCTAssertEqual(envelope.product, "AuthCompanion")
    XCTAssertEqual(envelope.state.pinentry.condition, .configured)
    XCTAssertEqual(envelope.state.pam.condition, .configured)
    XCTAssertEqual(
      runner.invocations,
      [
        ToolInvocation(executable: paths.pinentryExecutable, arguments: ["--version"]),
        ToolInvocation(executable: paths.pamExecutable, arguments: ["--version"]),
        ToolInvocation(
          executable: paths.pinentryExecutable,
          arguments: ["status", "--format", "json"]
        ),
      ])
    XCTAssertFalse(runner.invocations.contains { $0.executable == paths.sudoExecutable })
  }

  func testHumanDependencyFailureProvidesInstallRemediation() {
    let application = makeApplication(
      effectiveUserID: 501,
      locator: ApplicationLocator(error: DependencyError.notInstalled),
      runner: ApplicationRunner(results: [])
    )

    let output = application.run(["authcompanion", "status"])

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertTrue(output.stdout.isEmpty)
    XCTAssertTrue(output.stderr.contains("brew install"))
    XCTAssertTrue(output.stderr.contains("pinentry-companion"))
    XCTAssertTrue(output.stderr.contains("pam-companion"))
  }

  func testInvalidInvocationUsesUsageExitStatusWithoutResolvingDependencies() {
    let locator = ApplicationLocator(error: DependencyError.notInstalled)
    let application = makeApplication(
      effectiveUserID: 501,
      locator: locator,
      runner: ApplicationRunner(results: [])
    )

    let output = application.run(["authcompanion", "unknown"])

    XCTAssertEqual(output.exitStatus, 2)
    XCTAssertTrue(output.stderr.contains("usage:"))
    XCTAssertEqual(locator.locateCount, 0)
  }

  private func makeApplication(
    effectiveUserID: UInt32,
    locator: ApplicationLocator,
    runner: ApplicationRunner
  ) -> AuthCompanionApplication {
    AuthCompanionApplication(
      effectiveUserID: effectiveUserID,
      locator: locator,
      runner: runner,
      pamSnapshots: ApplicationPAMSnapshotReader()
    )
  }
}

private final class ApplicationLocator: ComponentLocating {
  private let result: Result<ComponentPaths, Error>
  private(set) var locateCount = 0

  init(paths: ComponentPaths) {
    result = .success(paths)
  }

  init(error: any Error) {
    result = .failure(error)
  }

  func locate() throws -> ComponentPaths {
    locateCount += 1
    return try result.get()
  }
}

private final class ApplicationRunner: ToolRunning {
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

private final class ApplicationPAMSnapshotReader: PAMSnapshotReading {
  func read() throws -> PAMSnapshot {
    PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_companion.so\nauth sufficient pam_tid.so\n".utf8),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
  }
}
