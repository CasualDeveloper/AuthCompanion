import Foundation

enum PinentryContractError: Error {
  case invalidEnvelope
  case mismatchedExitStatus
}

struct PinentryStatusContract: Decodable {
  let schemaVersion: Int
  let component: String
  let componentVersion: String
  let operation: String
  let outcome: SuiteOutcome
  let changed: Bool
  let diagnostics: [SuiteDiagnostic]
  let state: State

  struct State: Decodable {
    let gpgConfiguration: GPGConfiguration
  }

  struct GPGConfiguration: Decodable {
    let alignment: PinentryConfigurationAlignment
    let ownership: String
    let recoveryAvailable: Bool
  }
}

enum PinentryConfigurationAlignment: String, Decodable {
  case currentBinary
  case otherBinary
  case missing
  case ambiguous
  case unknown
}

struct PinentryPlanContract: Decodable {
  let schemaVersion: Int
  let component: String
  let componentVersion: String
  let operation: String
  let outcome: SuiteOutcome
  let changed: Bool
  let diagnostics: [SuiteDiagnostic]
  let state: State

  struct State: Decodable {
    let applicability: PinentryPlanApplicability
    let changeRequired: Bool
    let conflicts: [Conflict]
  }

  struct Conflict: Decodable {
    let code: String
    let message: String
  }
}

enum PinentryPlanApplicability: String, Decodable {
  case ready
  case blocked
}

struct PinentryMutationContract: Decodable {
  let schemaVersion: Int
  let component: String
  let componentVersion: String
  let operation: String
  let outcome: SuiteOutcome
  let changed: Bool
  let diagnostics: [SuiteDiagnostic]
  let state: State

  struct State: Decodable {
    let transactionState: String
    let safety: String
  }
}

enum PinentryContractDecoder {
  static func status(
    _ result: ToolResult, expectedVersion: String
  ) throws -> PinentryStatusContract {
    let envelope = try JSONDecoder().decode(PinentryStatusContract.self, from: result.stdout)
    try validateHeader(
      schemaVersion: envelope.schemaVersion,
      component: envelope.component,
      version: envelope.componentVersion,
      operation: envelope.operation,
      expectedOperation: "status",
      expectedVersion: expectedVersion
    )
    try validateExit(outcome: envelope.outcome, exitStatus: result.exitStatus)
    guard !envelope.changed else { throw PinentryContractError.invalidEnvelope }
    return envelope
  }

  static func plan(
    _ result: ToolResult, expectedVersion: String
  ) throws -> PinentryPlanContract {
    let envelope = try JSONDecoder().decode(PinentryPlanContract.self, from: result.stdout)
    try validateHeader(
      schemaVersion: envelope.schemaVersion,
      component: envelope.component,
      version: envelope.componentVersion,
      operation: envelope.operation,
      expectedOperation: "plan",
      expectedVersion: expectedVersion
    )
    try validateExit(outcome: envelope.outcome, exitStatus: result.exitStatus)
    guard validPlanState(envelope) else { throw PinentryContractError.invalidEnvelope }
    return envelope
  }

  static func mutation(
    _ result: ToolResult,
    operation: String,
    expectedVersion: String
  ) throws -> PinentryMutationContract {
    let envelope = try JSONDecoder().decode(PinentryMutationContract.self, from: result.stdout)
    try validateHeader(
      schemaVersion: envelope.schemaVersion,
      component: envelope.component,
      version: envelope.componentVersion,
      operation: envelope.operation,
      expectedOperation: operation,
      expectedVersion: expectedVersion
    )
    try validateExit(outcome: envelope.outcome, exitStatus: result.exitStatus)
    guard validMutationState(envelope) else { throw PinentryContractError.invalidEnvelope }
    return envelope
  }

  private static func validateHeader(
    schemaVersion: Int,
    component: String,
    version: String,
    operation: String,
    expectedOperation: String,
    expectedVersion: String
  ) throws {
    guard schemaVersion == 1,
      component == "pinentry-companion",
      SupportedComponentVersions.pinentryCompanion.contains(expectedVersion),
      version == expectedVersion,
      operation == expectedOperation
    else {
      throw PinentryContractError.invalidEnvelope
    }
  }

  private static func validateExit(outcome: SuiteOutcome, exitStatus: Int32) throws {
    let expectedSuccess = outcome == .ok || outcome == .warning
    guard (exitStatus == 0) == expectedSuccess else {
      throw PinentryContractError.mismatchedExitStatus
    }
  }

  private static func validMutationState(_ envelope: PinentryMutationContract) -> Bool {
    return
      switch (
        envelope.operation,
        envelope.outcome,
        envelope.changed,
        envelope.state.transactionState,
        envelope.state.safety
      )
    {
    case ("setup", .ok, true, "committed", "exactRestoreStateRecorded"),
      ("setup", .ok, false, "unchanged", "exactRestoreStateRecorded"),
      ("restore", .ok, true, "restored", "compareAndSwapVerified"),
      ("restore", .ok, false, "unchanged", "compareAndSwapVerified"),
      (_, .error, false, "notCommitted", "noMutationCommitted"),
      (_, .conflict, false, "notCommitted", "noMutationCommitted"),
      (_, .error, false, "rollbackFailed", "manualRecoveryRequired"),
      (_, .error, false, "indeterminate", "inspectionRequired"):
      true
    default:
      false
    }
  }

  private static func validPlanState(_ envelope: PinentryPlanContract) -> Bool {
    guard !envelope.changed else { return false }
    return
      switch (
        envelope.state.applicability,
        envelope.state.changeRequired,
        envelope.state.conflicts.isEmpty,
        envelope.outcome
      )
    {
    case (.ready, false, true, .ok),
      (.ready, true, true, .warning),
      (.blocked, _, false, .conflict):
      true
    default:
      false
    }
  }
}
