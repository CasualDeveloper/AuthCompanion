import XCTest

@testable import AuthCompanionCore

final class SuiteManagerTests: XCTestCase {
  func testStatusAndPlanArePassiveAndNeverInvokeSudo() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryStatusJSON()),
      .success(stdout: pinentryPlanJSON(changeRequired: false)),
    ])
    let snapshots = StubPAMSnapshotReader(snapshot: .configured)
    let manager = makeManager(runner: runner, snapshots: snapshots)

    let status = manager.status()
    let plan = manager.plan()

    XCTAssertEqual(status.envelope.outcome, .ok)
    XCTAssertEqual(status.envelope.state.pam.condition, .configured)
    XCTAssertEqual(plan.envelope.outcome, .ok)
    XCTAssertEqual(
      runner.invocations,
      [
        ToolInvocation(
          executable: paths.pinentryExecutable,
          arguments: ["status", "--format", "json"]
        ),
        ToolInvocation(
          executable: paths.pinentryExecutable,
          arguments: ["plan", "--format", "json"]
        ),
      ]
    )
    XCTAssertFalse(runner.invocations.contains { $0.executable == paths.sudoExecutable })
    XCTAssertEqual(snapshots.readCount, 2)
  }

  func testSetupPreflightsThenMutatesPinentryBeforePAMAndVerifiesHealth() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(stdout: Data("would install pam_companion.so and update sudo_local\n".utf8)),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      .success(stdout: Data("installed pam_companion.so and updated sudo_local\n".utf8)),
      .success(stdout: Data("ok: pam_companion.so is installed and sudo_local is managed\n".utf8)),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .configured))

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertEqual(result.envelope.outcome, .ok)
    XCTAssertTrue(result.envelope.changed)
    XCTAssertEqual(result.envelope.state.recovery, .notNeeded)
    XCTAssertEqual(
      runner.invocations,
      [
        ToolInvocation(executable: paths.pinentryExecutable, arguments: ["plan", "--format", "json"]),
        sudo([paths.pamExecutable, "setup", "--dry-run"]),
        ToolInvocation(
          executable: paths.pinentryExecutable,
          arguments: ["setup", "--yes", "--format", "json"]
        ),
        sudo([paths.pamExecutable, "setup"]),
        sudo([paths.pamExecutable, "doctor"]),
      ]
    )
  }

  func testTakeoverUsesOnlyPinentryCanonicalTakeoverForm() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      .success(),
      .success(),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .configured))

    _ = manager.setup(takeOver: true)

    XCTAssertEqual(
      runner.invocations[2],
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["setup", "--take-over", "--yes", "--format", "json"]
      )
    )
  }

  func testSetupStopsBeforePinentryMutationWhenPAMDryRunFails() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("unsupported PAM policy\n".utf8)),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .notConfigured))

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.exitStatus, 1)
    XCTAssertEqual(result.envelope.outcome, .error)
    XCTAssertEqual(result.envelope.state.recovery, .notNeeded)
    XCTAssertEqual(runner.invocations.count, 2)
  }

  func testSetupRollsPinentryBackWhenPAMApplyFails() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM setup failed\n".utf8)),
      .success(stdout: pinentryMutationJSON(
        operation: "restore",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      )),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .notConfigured))

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.exitStatus, 1)
    XCTAssertEqual(result.envelope.outcome, .error)
    XCTAssertEqual(result.envelope.state.recovery, .rolledBack)
    XCTAssertEqual(
      runner.invocations.last,
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["restore", "--yes", "--format", "json"]
      )
    )
  }

  func testSetupReportsManualRecoveryWhenCompensationFails() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM setup failed\n".utf8)),
      ToolResult(
        exitStatus: 1,
        stdout: pinentryMutationJSON(
          operation: "restore",
          outcome: "conflict",
          changed: false,
          transactionState: "notCommitted",
          safety: "noMutationCommitted"
        ),
        stderr: Data()
      ),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .notConfigured))

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.envelope.state.recovery, .manualRequired)
    XCTAssertEqual(result.envelope.outcome, .error)
  }

  func testSetupRestoresPAMThenPinentryWhenDoctorFailsAfterPAMCommit() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      .success(),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM doctor failed\n".utf8)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "restore",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      )),
    ])
    let manager = makeManager(
      runner: runner,
      snapshots: StubPAMSnapshotReader(snapshot: .notConfigured)
    )

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.envelope.state.recovery, .rolledBack)
    XCTAssertEqual(Array(runner.invocations.suffix(2)), [
      sudo([paths.pamExecutable, "restore"]),
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["restore", "--yes", "--format", "json"]
      ),
    ])
  }

  func testSetupReportsManualRecoveryWhenPAMRollbackFailsButStillRestoresPinentry() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      .success(),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM doctor failed\n".utf8)),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM restore failed\n".utf8)),
      .success(stdout: pinentryMutationJSON(
        operation: "restore",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      )),
    ])
    let manager = makeManager(
      runner: runner,
      snapshots: StubPAMSnapshotReader(snapshot: .notConfigured)
    )

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.envelope.state.recovery, .manualRequired)
    XCTAssertEqual(Array(runner.invocations.suffix(2)), [
      sudo([paths.pamExecutable, "restore"]),
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["restore", "--yes", "--format", "json"]
      ),
    ])
  }

  func testSetupRollsBackBothComponentsWhenVisiblePAMPostconditionFails() {
    let runner = RecordingToolRunner(results: [
      .success(stdout: pinentryPlanJSON(changeRequired: true)),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "committed",
        safety: "exactRestoreStateRecorded"
      )),
      .success(),
      .success(),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "restore",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      )),
    ])
    let manager = makeManager(
      runner: runner,
      snapshots: StubPAMSnapshotReader(snapshots: [.notConfigured, .notConfigured])
    )

    let result = manager.setup(takeOver: false)

    XCTAssertEqual(result.envelope.state.recovery, .rolledBack)
    XCTAssertEqual(result.envelope.diagnostics.first?.code, "pam.setup.postconditionFailed")
    XCTAssertEqual(Array(runner.invocations.suffix(2)), [
      sudo([paths.pamExecutable, "restore"]),
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["restore", "--yes", "--format", "json"]
      ),
    ])
  }

  func testRestoreStopsBeforePinentryWhenPAMRestoreFails() {
    let runner = RecordingToolRunner(results: [
      .success(),
      ToolResult(exitStatus: 1, stdout: Data(), stderr: Data("PAM restore failed\n".utf8)),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .configured))

    let result = manager.restore()

    XCTAssertEqual(result.exitStatus, 1)
    XCTAssertEqual(runner.invocations, [
      sudo([paths.pamExecutable, "restore", "--dry-run"]),
      sudo([paths.pamExecutable, "restore"]),
    ])
  }

  func testRestoreUsesPAMFirstThenPinentryMachineRestore() {
    let runner = RecordingToolRunner(results: [
      .success(),
      .success(),
      .success(stdout: pinentryMutationJSON(
        operation: "restore",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      )),
    ])
    let manager = makeManager(runner: runner, snapshots: StubPAMSnapshotReader(snapshot: .notConfigured))

    let result = manager.restore()

    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertEqual(result.envelope.outcome, .ok)
    XCTAssertEqual(runner.invocations, [
      sudo([paths.pamExecutable, "restore", "--dry-run"]),
      sudo([paths.pamExecutable, "restore"]),
      ToolInvocation(
        executable: paths.pinentryExecutable,
        arguments: ["restore", "--yes", "--format", "json"]
      ),
    ])
  }

  private let paths = ComponentPaths(
    pinentryExecutable: "/opt/homebrew/opt/pinentry-companion/bin/pinentry-companion",
    pamExecutable: "/opt/homebrew/opt/pam-companion/bin/pam-companion",
    sudoExecutable: "/usr/bin/sudo"
  )

  private func makeManager(
    runner: RecordingToolRunner,
    snapshots: StubPAMSnapshotReader
  ) -> AuthCompanionManager {
    AuthCompanionManager(paths: paths, runner: runner, pamSnapshots: snapshots)
  }

  private func sudo(_ arguments: [String]) -> ToolInvocation {
    ToolInvocation(executable: paths.sudoExecutable, arguments: arguments)
  }
}

private final class RecordingToolRunner: ToolRunning {
  private var results: [ToolResult]
  private(set) var invocations: [ToolInvocation] = []

  init(results: [ToolResult]) {
    self.results = results
  }

  func run(_ invocation: ToolInvocation) throws -> ToolResult {
    invocations.append(invocation)
    guard !results.isEmpty else { throw TestError.missingResult }
    return results.removeFirst()
  }
}

private final class StubPAMSnapshotReader: PAMSnapshotReading {
  private var snapshots: [PAMSnapshot]
  private(set) var readCount = 0

  init(snapshot: PAMCondition) {
    snapshots = [snapshot.snapshot]
  }

  init(snapshots: [PAMCondition]) {
    self.snapshots = snapshots.map(\.snapshot)
  }

  func read() throws -> PAMSnapshot {
    readCount += 1
    guard !snapshots.isEmpty else { throw TestError.missingResult }
    if snapshots.count == 1 {
      return snapshots[0]
    }
    return snapshots.removeFirst()
  }
}

private enum TestError: Error {
  case missingResult
}

private extension ToolResult {
  static func success(stdout: Data = Data()) -> ToolResult {
    ToolResult(exitStatus: 0, stdout: stdout, stderr: Data())
  }
}

private extension PAMCondition {
  var snapshot: PAMSnapshot {
    switch self {
    case .configured:
      PAMSnapshot(
        sudoLocal: Data("auth sufficient pam_companion.so\nauth sufficient pam_tid.so\n".utf8),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )
    case .legacy:
      PAMSnapshot(
        sudoLocal: Data("auth sufficient pam_watchid.so.2\n".utf8),
        canonicalModuleExists: false,
        legacyModuleExists: false,
        versionedLegacyModuleExists: true
      )
    case .notConfigured:
      .empty
    case .unmanaged:
      PAMSnapshot(
        sudoLocal: Data(),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )
    case .conflict:
      PAMSnapshot(
        sudoLocal: Data("auth required pam_companion.so\n".utf8),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )
    }
  }
}

let pinentryStatusJSONText = """
    {"schemaVersion":1,"component":"pinentry-companion","componentVersion":"0.2.0","operation":"status","outcome":"ok","changed":false,"diagnostics":[],"state":{"gpgConfiguration":{"alignment":"currentBinary","ownership":"managed","recoveryAvailable":true}}}
    """

func pinentryStatusJSON() -> Data {
  Data(pinentryStatusJSONText.utf8)
}

private func pinentryPlanJSON(changeRequired: Bool) -> Data {
  Data("""
    {"schemaVersion":1,"component":"pinentry-companion","componentVersion":"0.2.0","operation":"plan","outcome":"ok","changed":false,"diagnostics":[],"state":{"applicability":"ready","changeRequired":\(changeRequired),"conflicts":[]}}
    """.utf8)
}

func pinentryMutationJSON(
  operation: String,
  outcome: String = "ok",
  changed: Bool,
  transactionState: String,
  safety: String
) -> Data {
  Data("""
    {"schemaVersion":1,"component":"pinentry-companion","componentVersion":"0.2.0","operation":"\(operation)","outcome":"\(outcome)","changed":\(changed),"diagnostics":[],"state":{"transactionState":"\(transactionState)","safety":"\(safety)"}}
    """.utf8)
}
