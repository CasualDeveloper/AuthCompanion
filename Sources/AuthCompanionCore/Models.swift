import Foundation

public enum SuiteOutcome: String, Codable, Equatable, Sendable {
  case ok
  case warning
  case error
  case conflict
}

public enum DiagnosticSeverity: String, Codable, Equatable, Sendable {
  case info
  case warning
  case error
}

public struct SuiteDiagnostic: Codable, Equatable, Sendable {
  public let code: String
  public let severity: DiagnosticSeverity
  public let message: String
  public let remediation: String?

  public init(
    code: String,
    severity: DiagnosticSeverity,
    message: String,
    remediation: String? = nil
  ) {
    self.code = code
    self.severity = severity
    self.message = message
    self.remediation = remediation
  }
}

public enum ComponentCondition: String, Codable, Equatable, Sendable {
  case configured
  case ready
  case notConfigured
  case legacy
  case unmanaged
  case conflict
  case unavailable
  case healthy
  case restored
}

public struct ComponentStatus: Codable, Equatable, Sendable {
  public let component: String
  public let version: String?
  public let condition: ComponentCondition
  public let verification: String

  public init(
    component: String,
    version: String?,
    condition: ComponentCondition,
    verification: String
  ) {
    self.component = component
    self.version = version
    self.condition = condition
    self.verification = verification
  }
}

public struct StatusState: Codable, Equatable, Sendable {
  public let pinentry: ComponentStatus
  public let pam: ComponentStatus
}

public struct PlanStep: Codable, Equatable, Sendable {
  public let component: String
  public let action: String
  public let requiresAdministrator: Bool
  public let reversible: Bool
}

public struct PlanState: Codable, Equatable, Sendable {
  public let pinentry: ComponentStatus
  public let pam: ComponentStatus
  public let sequence: [PlanStep]
}

public enum RecoveryState: String, Codable, Equatable, Sendable {
  case notNeeded
  case rolledBack
  case manualRequired
}

public struct MutationState: Codable, Equatable, Sendable {
  public let pinentry: ComponentStatus
  public let pam: ComponentStatus
  public let recovery: RecoveryState
}

public struct DoctorState: Codable, Equatable, Sendable {
  public let pinentry: ComponentStatus
  public let pam: ComponentStatus
}

public struct FailureState: Codable, Equatable, Sendable {
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }
}

public struct AuthEnvelope<State: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let product: String
  public let productVersion: String
  public let operation: String
  public let outcome: SuiteOutcome
  public let changed: Bool
  public let diagnostics: [SuiteDiagnostic]
  public let state: State

  public init(
    operation: String,
    outcome: SuiteOutcome,
    changed: Bool,
    diagnostics: [SuiteDiagnostic],
    state: State
  ) {
    schemaVersion = 1
    product = "AuthCompanion"
    productVersion = AuthCompanionVersion.current
    self.operation = operation
    self.outcome = outcome
    self.changed = changed
    self.diagnostics = diagnostics
    self.state = state
  }
}

public struct AuthCommandResult<State: Codable & Equatable & Sendable>: Equatable, Sendable {
  public let envelope: AuthEnvelope<State>
  public let exitStatus: Int32
}
