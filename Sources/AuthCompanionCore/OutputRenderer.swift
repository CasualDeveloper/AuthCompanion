import Foundation

enum AuthOutputRenderer {
  static let help = """
    AuthCompanion configures pinentry-companion and pam-companion together.

    Usage:
      authcompanion status [--format json]
      authcompanion plan [--format json]
      authcompanion setup --yes [--take-over] [--format json]
      authcompanion restore --yes [--format json]
      authcompanion doctor [--format json]
      authcompanion --version
      authcompanion --help

    Run AuthCompanion as your login user. It invokes sudo only for the
    pam-companion lifecycle commands that require administrator access.
    """

  static func status(_ result: AuthCommandResult<StatusState>) -> String {
    """
    AuthCompanion status
    pinentry-companion: \(describe(result.envelope.state.pinentry))
    pam-companion: \(describe(result.envelope.state.pam))
    \(diagnostics(result.envelope.diagnostics))
    """.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func plan(_ result: AuthCommandResult<PlanState>) -> String {
    let steps = result.envelope.state.sequence.enumerated().map { index, step in
      let privilege = step.requiresAdministrator ? " (administrator)" : ""
      return "\(index + 1). \(step.component): \(step.action)\(privilege)"
    }.joined(separator: "\n")
    let next =
      result.exitStatus == 0
      ? "Run `authcompanion setup --yes` to apply this plan."
      : "Resolve the reported conflicts, then run the plan again."
    return """
      AuthCompanion plan
      \(steps)
      \(next)
      \(diagnostics(result.envelope.diagnostics))
      """.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func mutation(
    _ result: AuthCommandResult<MutationState>,
    operation: String
  ) -> String {
    let verb = result.exitStatus == 0 ? "complete" : "failed"
    return """
      AuthCompanion \(operation) \(verb).
      pinentry-companion: \(describe(result.envelope.state.pinentry))
      pam-companion: \(describe(result.envelope.state.pam))
      recovery: \(result.envelope.state.recovery.rawValue)
      \(diagnostics(result.envelope.diagnostics))
      """.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func doctor(_ result: AuthCommandResult<DoctorState>) -> String {
    """
    AuthCompanion doctor
    pinentry-companion: \(describe(result.envelope.state.pinentry))
    pam-companion: \(describe(result.envelope.state.pam))
    \(diagnostics(result.envelope.diagnostics))
    """.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func json<State>(_ envelope: AuthEnvelope<State>) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(envelope), as: UTF8.self)
  }

  private static func describe(_ status: ComponentStatus) -> String {
    let version = status.version.map { " \($0)" } ?? ""
    return "\(status.condition.rawValue)\(version) [\(status.verification)]"
  }

  private static func diagnostics(_ values: [SuiteDiagnostic]) -> String {
    values.map { diagnostic in
      let remediation = diagnostic.remediation.map { " Fix: \($0)" } ?? ""
      return "\(diagnostic.severity.rawValue): \(diagnostic.message)\(remediation)"
    }.joined(separator: "\n")
  }
}
