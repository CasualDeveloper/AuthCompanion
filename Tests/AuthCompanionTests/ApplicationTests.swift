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
    XCTAssertEqual(version.stdout, "authcompanion 0.2.0\n")
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
        stdout: Data("pam-companion 0.1.1\n".utf8),
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

  func testRollingUpgradeStatusPreservesObservedComponentVersions() throws {
    for pinentry in ["0.2.0", "0.2.1"] {
      for pam in ["0.1.1", "0.2.0"] {
        let response = pinentryStatusJSONText.replacingOccurrences(
          of: "\"componentVersion\":\"0.2.0\"",
          with: "\"componentVersion\":\"\(pinentry)\""
        )
        let runner = ApplicationRunner(results: [
          ToolResult(
            exitStatus: 0, stdout: Data("pinentry-companion \(pinentry)\n".utf8), stderr: Data()),
          ToolResult(
            exitStatus: 0, stdout: Data("pam-companion \(pam)\n".utf8), stderr: Data()),
          ToolResult(exitStatus: 0, stdout: Data(response.utf8), stderr: Data()),
        ])
        let application = makeApplication(
          effectiveUserID: 501, locator: ApplicationLocator(paths: fixedPaths()), runner: runner)

        let output = application.run(["authcompanion", "status", "--format", "json"])

        XCTAssertEqual(output.exitStatus, 0, "pinentry \(pinentry), PAM \(pam)")
        guard output.exitStatus == 0 else { continue }
        let envelope = try JSONDecoder().decode(
          AuthEnvelope<StatusState>.self, from: Data(output.stdout.utf8))
        XCTAssertEqual(envelope.state.pinentry.version, pinentry)
        XCTAssertEqual(envelope.state.pam.version, pam)
        XCTAssertEqual(runner.invocations.count, 3)
        XCTAssertFalse(runner.invocations.contains { $0.executable == "/usr/bin/sudo" })
      }
    }
  }

  func testRollingUpgradeLifecycleUsesTheCommonPAMCommandSurface() throws {
    for pinentry in ["0.2.0", "0.2.1"] {
      for pam in ["0.1.1", "0.2.0"] {
        let prefix = [
          ToolResult(
            exitStatus: 0, stdout: Data("pinentry-companion \(pinentry)\n".utf8), stderr: Data()),
          ToolResult(
            exitStatus: 0, stdout: Data("pam-companion \(pam)\n".utf8), stderr: Data()),
          ToolResult(exitStatus: 0, stdout: Data(), stderr: Data()),
        ]
        let success = ToolResult(exitStatus: 0, stdout: Data(), stderr: Data())
        func response(_ data: Data) -> ToolResult {
          ToolResult(
            exitStatus: 0,
            stdout: Data(
              String(decoding: data, as: UTF8.self).replacingOccurrences(
                of: "\"componentVersion\":\"0.2.0\"",
                with: "\"componentVersion\":\"\(pinentry)\""
              ).utf8),
            stderr: Data()
          )
        }
        let operations: [(arguments: [String], results: [ToolResult], pamCommands: [[String]])] = [
          (
            ["setup", "--yes", "--format", "json"],
            [
              response(pinentryPlanJSON(changeRequired: true)), success,
              response(
                pinentryMutationJSON(
                  operation: "setup", changed: true, transactionState: "committed",
                  safety: "exactRestoreStateRecorded")),
              success, success,
            ],
            [["setup", "--dry-run"], ["setup"], ["doctor"]]
          ),
          (
            ["restore", "--yes", "--format", "json"],
            [
              success, success,
              response(
                pinentryMutationJSON(
                  operation: "restore", changed: true, transactionState: "restored",
                  safety: "compareAndSwapVerified")),
            ],
            [["restore", "--dry-run"], ["restore"]]
          ),
          (["doctor", "--format", "json"], [success, success], [["doctor"]]),
        ]
        for operation in operations {
          let runner = ApplicationRunner(results: prefix + operation.results)
          let application = makeApplication(
            effectiveUserID: 501, locator: ApplicationLocator(paths: fixedPaths()), runner: runner)

          let output = application.run(["authcompanion"] + operation.arguments)

          XCTAssertEqual(output.exitStatus, 0, "\(pinentry), \(pam): \(operation.arguments)")
          let envelope =
            try JSONSerialization.jsonObject(with: Data(output.stdout.utf8))
            as? [String: Any]
          let state = try XCTUnwrap(envelope?["state"] as? [String: Any])
          XCTAssertEqual((state["pinentry"] as? [String: Any])?["version"] as? String, pinentry)
          XCTAssertEqual((state["pam"] as? [String: Any])?["version"] as? String, pam)
          let pamInvocations = runner.invocations.filter {
            $0.executable == "/usr/bin/sudo" && $0.arguments.contains("/fixed/pam-companion")
          }
          XCTAssertEqual(
            pamInvocations.map(\.arguments),
            operation.pamCommands.map { ["-n", "--", "/fixed/pam-companion"] + $0 }
          )
        }
      }
    }
  }

  func testUnknownComponentVersionStopsBeforePrivilegeOrLifecycleWork() {
    let runner = ApplicationRunner(results: [
      ToolResult(
        exitStatus: 0, stdout: Data("pinentry-companion 0.2.2\n".utf8), stderr: Data())
    ])
    let application = makeApplication(
      effectiveUserID: 501, locator: ApplicationLocator(paths: fixedPaths()), runner: runner)

    let output = application.run(["authcompanion", "setup", "--yes", "--format", "json"])

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertEqual(runner.invocations.count, 1)
    XCTAssertTrue(output.stdout.contains("unsupported pinentry-companion version"))
    XCTAssertTrue(output.stdout.contains("Upgrade authcompanion"))
  }

  func testVersionChangeBetweenProbeAndPlanStopsBeforeMutation() {
    let changedVersion = String(decoding: pinentryPlanJSON(changeRequired: true), as: UTF8.self)
      .replacingOccurrences(
        of: "\"componentVersion\":\"0.2.0\"",
        with: "\"componentVersion\":\"0.2.1\"")
    let runner = ApplicationRunner(
      results: versionResults() + [
        ToolResult(exitStatus: 0, stdout: Data(), stderr: Data()),
        ToolResult(exitStatus: 0, stdout: Data(changedVersion.utf8), stderr: Data()),
      ])
    let application = makeApplication(
      effectiveUserID: 501, locator: ApplicationLocator(paths: fixedPaths()), runner: runner)

    let output = application.run(["authcompanion", "setup", "--yes", "--format", "json"])

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertEqual(runner.invocations.count, 4)
    XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("setup") })
    XCTAssertTrue(output.stdout.contains("pinentry-companion.unavailable"))
  }

  func testPrivilegedCommandsRequireSudoAuthorizationBeforeManagerWork() {
    for arguments in [
      ["authcompanion", "setup", "--yes"],
      ["authcompanion", "restore", "--yes"],
      ["authcompanion", "doctor"],
    ] {
      let paths = fixedPaths()
      let runner = ApplicationRunner(
        results: versionResults() + [
          ToolResult(exitStatus: 1, stdout: Data(), stderr: Data())
        ])
      let application = makeApplication(
        effectiveUserID: 501,
        locator: ApplicationLocator(paths: paths),
        runner: runner
      )

      let output = application.run(arguments)

      XCTAssertEqual(output.exitStatus, 1, "arguments: \(arguments)")
      XCTAssertTrue(output.stderr.contains("sudo -v"), "arguments: \(arguments)")
      XCTAssertEqual(
        runner.invocations.last,
        ToolInvocation(
          executable: paths.sudoExecutable,
          arguments: ["-n", "--", "/usr/bin/true"]
        ))
      XCTAssertEqual(runner.invocations.count, 3)
    }
  }

  func testJSONAuthorizationFailureUsesStableDiagnostic() throws {
    let runner = ApplicationRunner(
      results: versionResults() + [
        ToolResult(exitStatus: 1, stdout: Data(), stderr: Data())
      ])
    let application = makeApplication(
      effectiveUserID: 501,
      locator: ApplicationLocator(paths: fixedPaths()),
      runner: runner
    )

    let output = application.run([
      "authcompanion", "restore", "--yes", "--format", "json",
    ])
    let envelope = try JSONDecoder().decode(
      AuthEnvelope<FailureState>.self, from: Data(output.stdout.utf8))

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertEqual(envelope.diagnostics.first?.code, "sudo.authorizationRequired")
    XCTAssertEqual(runner.invocations.count, 3)
  }

  func testAuthorizationProbeErrorUsesSameRemediation() {
    let runner = ApplicationRunner(
      results: versionResults(),
      errorAfterResults: DependencyError.notInstalled
    )
    let application = makeApplication(
      effectiveUserID: 501,
      locator: ApplicationLocator(paths: fixedPaths()),
      runner: runner
    )

    let output = application.run(["authcompanion", "doctor"])

    XCTAssertEqual(output.exitStatus, 1)
    XCTAssertTrue(output.stderr.contains("sudo -v"))
    XCTAssertEqual(runner.invocations.count, 3)
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

  private func fixedPaths() -> ComponentPaths {
    ComponentPaths(
      pinentryExecutable: "/fixed/pinentry-companion",
      pamExecutable: "/fixed/pam-companion",
      sudoExecutable: "/usr/bin/sudo"
    )
  }

  private func versionResults() -> [ToolResult] {
    [
      ToolResult(
        exitStatus: 0,
        stdout: Data("pinentry-companion 0.2.0\n".utf8),
        stderr: Data()
      ),
      ToolResult(
        exitStatus: 0,
        stdout: Data("pam-companion 0.1.1\n".utf8),
        stderr: Data()
      ),
    ]
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
  private let errorAfterResults: (any Error)?
  private(set) var invocations: [ToolInvocation] = []

  init(results: [ToolResult], errorAfterResults: (any Error)? = nil) {
    self.results = results
    self.errorAfterResults = errorAfterResults
  }

  func run(_ invocation: ToolInvocation) throws -> ToolResult {
    invocations.append(invocation)
    guard !results.isEmpty else {
      throw errorAfterResults ?? DependencyError.notInstalled
    }
    return results.removeFirst()
  }
}

private final class ApplicationPAMSnapshotReader: PAMSnapshotReading {
  func read() throws -> PAMSnapshot {
    PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_tid.so\n".utf8),
      canonicalModuleExists: false,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
  }
}
