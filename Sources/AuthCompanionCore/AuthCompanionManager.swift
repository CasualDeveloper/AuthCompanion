import Foundation

public final class AuthCompanionManager {
  private let paths: ComponentPaths
  private let runner: any ToolRunning
  private let pamSnapshots: any PAMSnapshotReading

  public init(
    paths: ComponentPaths,
    runner: any ToolRunning,
    pamSnapshots: any PAMSnapshotReading
  ) {
    self.paths = paths
    self.runner = runner
    self.pamSnapshots = pamSnapshots
  }

  public func status() -> AuthCommandResult<StatusState> {
    var diagnostics: [SuiteDiagnostic] = []
    let pinentry: ComponentStatus
    do {
      let result = try runner.run(pinentryInvocation(["status", "--format", "json"]))
      let contract = try PinentryContractDecoder.status(result)
      pinentry = pinentryStatus(contract)
      diagnostics += contract.diagnostics
    } catch {
      pinentry = unavailable(component: "pinentry-companion")
      diagnostics.append(componentFailure("pinentry-companion", error: error))
    }

    let pam = visiblePAMStatus(diagnostics: &diagnostics)
    let outcome: SuiteOutcome
    if diagnostics.contains(where: { $0.severity == .error }) {
      outcome = .error
    } else if pinentry.condition == .configured && pam.condition == .configured {
      outcome = .ok
    } else {
      outcome = .warning
    }
    return result(
      operation: "status",
      outcome: outcome,
      changed: false,
      diagnostics: diagnostics,
      state: StatusState(pinentry: pinentry, pam: pam),
      exitStatus: outcome == .error ? 1 : 0
    )
  }

  public func plan() -> AuthCommandResult<PlanState> {
    var diagnostics: [SuiteDiagnostic] = []
    let pinentry: ComponentStatus
    var pinentryChangeRequired = false
    do {
      let result = try runner.run(pinentryInvocation(["plan", "--format", "json"]))
      let contract = try PinentryContractDecoder.plan(result)
      pinentryChangeRequired = contract.state.changeRequired
      pinentry = ComponentStatus(
        component: "pinentry-companion",
        version: contract.componentVersion,
        condition: contract.state.applicability == .ready ? .ready : .conflict,
        verification: "machineContractV1"
      )
      diagnostics += contract.diagnostics
    } catch {
      pinentry = unavailable(component: "pinentry-companion")
      diagnostics.append(componentFailure("pinentry-companion", error: error))
    }

    let pam = visiblePAMStatus(diagnostics: &diagnostics)
    let blocked =
      pinentry.condition == .unavailable || pinentry.condition == .conflict
      || pam.condition == .conflict
    let sequence = [
      PlanStep(
        component: "pam-companion",
        action: "preflight PAM configuration",
        requiresAdministrator: true,
        reversible: true
      ),
      PlanStep(
        component: "pinentry-companion",
        action: pinentryChangeRequired ? "configure GPG pinentry" : "adopt or verify GPG pinentry",
        requiresAdministrator: false,
        reversible: true
      ),
      PlanStep(
        component: "pam-companion",
        action: pam.condition == .configured
          ? "verify managed PAM state"
          : "configure and verify PAM",
        requiresAdministrator: true,
        reversible: true
      ),
    ]
    return result(
      operation: "plan",
      outcome: blocked ? .conflict : .ok,
      changed: false,
      diagnostics: diagnostics,
      state: PlanState(pinentry: pinentry, pam: pam, sequence: sequence),
      exitStatus: blocked ? 1 : 0
    )
  }

  public func setup(takeOver: Bool) -> AuthCommandResult<MutationState> {
    var diagnostics: [SuiteDiagnostic] = []
    let originalPAM = visiblePAMStatus(diagnostics: &diagnostics)

    let plan: PinentryPlanContract
    do {
      plan = try PinentryContractDecoder.plan(
        runner.run(pinentryInvocation(["plan", "--format", "json"]))
      )
      let onlyTakeoverConflict =
        !plan.state.conflicts.isEmpty
        && plan.state.conflicts.allSatisfy { $0.code == "foreignPinentryProgram" }
      guard plan.state.applicability == .ready || (takeOver && onlyTakeoverConflict) else {
        return mutationFailure(
          operation: "setup",
          diagnostic: SuiteDiagnostic(
            code: "pinentry.plan.blocked",
            severity: .error,
            message: "pinentry-companion cannot safely apply its current plan.",
            remediation: "Run pinentry-companion plan --format json and resolve its conflicts."
          ),
          pinentry: component(from: plan),
          pam: originalPAM,
          recovery: .notNeeded
        )
      }
    } catch {
      return mutationFailure(
        operation: "setup",
        diagnostic: componentFailure("pinentry-companion", error: error),
        pinentry: unavailable(component: "pinentry-companion"),
        pam: originalPAM,
        recovery: .notNeeded
      )
    }

    do {
      let dryRun = try runner.run(sudoInvocation([paths.pamExecutable, "setup", "--dry-run"]))
      guard dryRun.exitStatus == 0 else {
        return mutationFailure(
          operation: "setup",
          diagnostic: toolFailure("pam.setup.preflightFailed", result: dryRun),
          pinentry: component(from: plan),
          pam: originalPAM,
          recovery: .notNeeded
        )
      }
    } catch {
      return mutationFailure(
        operation: "setup",
        diagnostic: componentFailure("pam-companion", error: error),
        pinentry: component(from: plan),
        pam: originalPAM,
        recovery: .notNeeded
      )
    }

    let setupArguments =
      takeOver
      ? ["setup", "--take-over", "--yes", "--format", "json"]
      : ["setup", "--yes", "--format", "json"]
    let pinentryMutation: PinentryMutationContract
    do {
      pinentryMutation = try PinentryContractDecoder.mutation(
        runner.run(pinentryInvocation(setupArguments)),
        operation: "setup"
      )
      guard pinentryMutation.outcome == .ok else {
        return mutationFailure(
          operation: "setup",
          diagnostic: SuiteDiagnostic(
            code: "pinentry.setup.failed",
            severity: .error,
            message: "pinentry-companion did not commit setup."
          ),
          pinentry: component(from: pinentryMutation),
          pam: originalPAM,
          recovery: recovery(from: pinentryMutation)
        )
      }
    } catch {
      return mutationFailure(
        operation: "setup",
        diagnostic: componentFailure("pinentry-companion", error: error),
        pinentry: unavailable(component: "pinentry-companion"),
        pam: originalPAM,
        recovery: .manualRequired
      )
    }

    let pamSetup: ToolResult
    do {
      pamSetup = try runner.run(sudoInvocation([paths.pamExecutable, "setup"]))
    } catch {
      return rollbackSetup(
        after: pinentryMutation,
        pamWasApplied: false,
        primaryDiagnostic: componentFailure("pam-companion", error: error),
        originalPAM: originalPAM
      )
    }
    guard pamSetup.exitStatus == 0 else {
      return rollbackSetup(
        after: pinentryMutation,
        pamWasApplied: false,
        primaryDiagnostic: toolFailure("pam.setup.failed", result: pamSetup),
        originalPAM: originalPAM
      )
    }

    let doctor: ToolResult
    do {
      doctor = try runner.run(sudoInvocation([paths.pamExecutable, "doctor"]))
    } catch {
      return rollbackSetup(
        after: pinentryMutation,
        pamWasApplied: true,
        primaryDiagnostic: componentFailure("pam-companion", error: error),
        originalPAM: originalPAM
      )
    }
    guard doctor.exitStatus == 0 else {
      return rollbackSetup(
        after: pinentryMutation,
        pamWasApplied: true,
        primaryDiagnostic: toolFailure("pam.doctor.failed", result: doctor),
        originalPAM: originalPAM
      )
    }

    let configuredPAM = visiblePAMStatus(diagnostics: &diagnostics)
    guard configuredPAM.condition == .configured else {
      return rollbackSetup(
        after: pinentryMutation,
        pamWasApplied: true,
        primaryDiagnostic: SuiteDiagnostic(
          code: "pam.setup.postconditionFailed",
          severity: .error,
          message: "Visible PAM state did not match the configured postcondition."
        ),
        originalPAM: originalPAM
      )
    }

    diagnostics += pinentryMutation.diagnostics
    return result(
      operation: "setup",
      outcome: .ok,
      changed: pinentryMutation.changed || originalPAM.condition != .configured,
      diagnostics: diagnostics,
      state: MutationState(
        pinentry: component(from: pinentryMutation),
        pam: configuredPAM,
        recovery: .notNeeded
      )
    )
  }

  public func restore() -> AuthCommandResult<MutationState> {
    var diagnostics: [SuiteDiagnostic] = []
    let originalPAM = visiblePAMStatus(diagnostics: &diagnostics)
    do {
      let dryRun = try runner.run(sudoInvocation([paths.pamExecutable, "restore", "--dry-run"]))
      guard dryRun.exitStatus == 0 else {
        return mutationFailure(
          operation: "restore",
          diagnostic: toolFailure("pam.restore.preflightFailed", result: dryRun),
          pinentry: unavailable(component: "pinentry-companion"),
          pam: originalPAM,
          recovery: .notNeeded
        )
      }
      let pamRestore = try runner.run(sudoInvocation([paths.pamExecutable, "restore"]))
      guard pamRestore.exitStatus == 0 else {
        return mutationFailure(
          operation: "restore",
          diagnostic: toolFailure("pam.restore.failed", result: pamRestore),
          pinentry: unavailable(component: "pinentry-companion"),
          pam: originalPAM,
          recovery: .notNeeded
        )
      }
    } catch {
      return mutationFailure(
        operation: "restore",
        diagnostic: componentFailure("pam-companion", error: error),
        pinentry: unavailable(component: "pinentry-companion"),
        pam: originalPAM,
        recovery: .manualRequired
      )
    }

    do {
      let pinentry = try PinentryContractDecoder.mutation(
        runner.run(pinentryInvocation(["restore", "--yes", "--format", "json"])),
        operation: "restore"
      )
      guard pinentry.outcome == .ok else {
        return mutationFailure(
          operation: "restore",
          diagnostic: SuiteDiagnostic(
            code: "pinentry.restore.failed",
            severity: .error,
            message: "PAM was restored, but pinentry-companion could not restore GPG state.",
            remediation: "Rerun authcompanion restore --yes."
          ),
          pinentry: component(from: pinentry),
          pam: restoredPAMStatus(),
          recovery: recovery(from: pinentry)
        )
      }
      return result(
        operation: "restore",
        outcome: .ok,
        changed: true,
        diagnostics: pinentry.diagnostics,
        state: MutationState(
          pinentry: component(from: pinentry),
          pam: restoredPAMStatus(),
          recovery: .notNeeded
        )
      )
    } catch {
      return mutationFailure(
        operation: "restore",
        diagnostic: componentFailure("pinentry-companion", error: error),
        pinentry: unavailable(component: "pinentry-companion"),
        pam: restoredPAMStatus(),
        recovery: .manualRequired
      )
    }
  }

  public func doctor() -> AuthCommandResult<DoctorState> {
    var diagnostics: [SuiteDiagnostic] = []
    let pinentry: ComponentStatus
    do {
      let result = try runner.run(pinentryInvocation(["doctor"]))
      pinentry =
        result.exitStatus == 0
        ? ComponentStatus(
          component: "pinentry-companion",
          version: PinentryContractDecoder.supportedVersion,
          condition: .healthy,
          verification: "componentDoctor"
        )
        : unavailable(component: "pinentry-companion")
      if result.exitStatus != 0 {
        diagnostics.append(toolFailure("pinentry.doctor.failed", result: result))
      }
    } catch {
      pinentry = unavailable(component: "pinentry-companion")
      diagnostics.append(componentFailure("pinentry-companion", error: error))
    }

    let pam: ComponentStatus
    do {
      let result = try runner.run(sudoInvocation([paths.pamExecutable, "doctor"]))
      pam =
        result.exitStatus == 0
        ? ComponentStatus(
          component: "pam-companion",
          version: SupportedComponentVersions.pamCompanion,
          condition: .healthy,
          verification: "componentDoctor"
        )
        : unavailable(component: "pam-companion")
      if result.exitStatus != 0 {
        diagnostics.append(toolFailure("pam.doctor.failed", result: result))
      }
    } catch {
      pam = unavailable(component: "pam-companion")
      diagnostics.append(componentFailure("pam-companion", error: error))
    }
    let healthy = pinentry.condition == .healthy && pam.condition == .healthy
    return result(
      operation: "doctor",
      outcome: healthy ? .ok : .error,
      changed: false,
      diagnostics: diagnostics,
      state: DoctorState(pinentry: pinentry, pam: pam),
      exitStatus: healthy ? 0 : 1
    )
  }

  private func rollbackSetup(
    after mutation: PinentryMutationContract,
    pamWasApplied: Bool,
    primaryDiagnostic: SuiteDiagnostic,
    originalPAM: ComponentStatus
  ) -> AuthCommandResult<MutationState> {
    var diagnostics = [primaryDiagnostic]
    var pamRecovered = !pamWasApplied
    if pamWasApplied {
      do {
        let restore = try runner.run(sudoInvocation([paths.pamExecutable, "restore"]))
        pamRecovered = restore.exitStatus == 0
        if !pamRecovered {
          diagnostics.append(toolFailure("pam.rollback.failed", result: restore))
        }
      } catch {
        diagnostics.append(componentFailure("pam-companion.rollback", error: error))
      }
    }

    var pinentry = component(from: mutation)
    var pinentryRecovered = !mutation.changed
    if mutation.changed {
      do {
        let restore = try PinentryContractDecoder.mutation(
          runner.run(pinentryInvocation(["restore", "--yes", "--format", "json"])),
          operation: "restore"
        )
        pinentry = component(from: restore)
        pinentryRecovered = restore.outcome == .ok
        diagnostics += restore.diagnostics
        if !pinentryRecovered {
          diagnostics.append(
            SuiteDiagnostic(
              code: "pinentry.rollback.failed",
              severity: .error,
              message: "pinentry-companion could not restore its pre-setup state.",
              remediation: "Run pinentry-companion restore --yes --format json."
            ))
        }
      } catch {
        pinentry = unavailable(component: "pinentry-companion")
        diagnostics.append(componentFailure("pinentry-companion.rollback", error: error))
      }
    }

    let rollbackAttempted = pamWasApplied || mutation.changed
    let recovery: RecoveryState =
      pamRecovered && pinentryRecovered
      ? (rollbackAttempted ? .rolledBack : .notNeeded)
      : .manualRequired
    return result(
      operation: "setup",
      outcome: .error,
      changed: recovery == .manualRequired,
      diagnostics: diagnostics,
      state: MutationState(
        pinentry: pinentry,
        pam: pamRecovered ? originalPAM : unavailable(component: "pam-companion"),
        recovery: recovery
      ),
      exitStatus: 1
    )
  }

  private func visiblePAMStatus(diagnostics: inout [SuiteDiagnostic]) -> ComponentStatus {
    do {
      let condition = try PAMInspector.inspect(pamSnapshots.read())
      return ComponentStatus(
        component: "pam-companion",
        version: condition == .configured ? SupportedComponentVersions.pamCompanion : nil,
        condition: componentCondition(condition),
        verification: "visibleFilesystem"
      )
    } catch {
      diagnostics.append(componentFailure("pam-companion", error: error))
      return unavailable(component: "pam-companion")
    }
  }

  private func restoredPAMStatus() -> ComponentStatus {
    ComponentStatus(
      component: "pam-companion",
      version: SupportedComponentVersions.pamCompanion,
      condition: .restored,
      verification: "componentLifecycle"
    )
  }

  private func pinentryStatus(_ contract: PinentryStatusContract) -> ComponentStatus {
    let condition: ComponentCondition
    switch contract.state.gpgConfiguration.alignment {
    case .currentBinary: condition = .configured
    case .missing: condition = .notConfigured
    case .otherBinary, .ambiguous, .unknown: condition = .conflict
    }
    return ComponentStatus(
      component: "pinentry-companion",
      version: contract.componentVersion,
      condition: condition,
      verification: "machineContractV1"
    )
  }

  private func component(from plan: PinentryPlanContract) -> ComponentStatus {
    ComponentStatus(
      component: "pinentry-companion",
      version: plan.componentVersion,
      condition: plan.state.applicability == .ready ? .ready : .conflict,
      verification: "machineContractV1"
    )
  }

  private func component(from mutation: PinentryMutationContract) -> ComponentStatus {
    let condition: ComponentCondition
    switch mutation.state.transactionState {
    case "committed", "unchanged": condition = .configured
    case "restored": condition = .restored
    default: condition = .conflict
    }
    return ComponentStatus(
      component: "pinentry-companion",
      version: mutation.componentVersion,
      condition: condition,
      verification: "machineContractV1"
    )
  }

  private func recovery(from mutation: PinentryMutationContract) -> RecoveryState {
    switch mutation.state.safety {
    case "manualRecoveryRequired", "inspectionRequired": .manualRequired
    case "compareAndSwapVerified": .rolledBack
    default: .notNeeded
    }
  }

  private func componentCondition(_ condition: PAMCondition) -> ComponentCondition {
    switch condition {
    case .configured: .configured
    case .notConfigured: .notConfigured
    case .legacy: .legacy
    case .unmanaged: .unmanaged
    case .conflict: .conflict
    }
  }

  private func unavailable(component: String) -> ComponentStatus {
    ComponentStatus(
      component: component,
      version: nil,
      condition: .unavailable,
      verification: "unavailable"
    )
  }

  private func pinentryInvocation(_ arguments: [String]) -> ToolInvocation {
    ToolInvocation(executable: paths.pinentryExecutable, arguments: arguments)
  }

  private func sudoInvocation(_ arguments: [String]) -> ToolInvocation {
    ToolInvocation(executable: paths.sudoExecutable, arguments: arguments)
  }

  private func componentFailure(_ component: String, error: any Error) -> SuiteDiagnostic {
    SuiteDiagnostic(
      code: "\(component).unavailable",
      severity: .error,
      message: "\(component) could not complete its fixed contract: \(error)",
      remediation: "Reinstall the supported Homebrew formula and retry."
    )
  }

  private func toolFailure(_ code: String, result: ToolResult) -> SuiteDiagnostic {
    let detail = String(data: result.stderr, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let message =
      if let detail, !detail.isEmpty {
        detail
      } else {
        "The component command failed."
      }
    return SuiteDiagnostic(
      code: code,
      severity: .error,
      message: message,
      remediation: "Run the component command directly for its recovery guidance."
    )
  }

  private func mutationFailure(
    operation: String,
    diagnostic: SuiteDiagnostic,
    pinentry: ComponentStatus,
    pam: ComponentStatus,
    recovery: RecoveryState
  ) -> AuthCommandResult<MutationState> {
    result(
      operation: operation,
      outcome: diagnostic.code.contains("conflict") ? .conflict : .error,
      changed: false,
      diagnostics: [diagnostic],
      state: MutationState(pinentry: pinentry, pam: pam, recovery: recovery),
      exitStatus: 1
    )
  }

  private func result<State: Codable & Equatable & Sendable>(
    operation: String,
    outcome: SuiteOutcome,
    changed: Bool,
    diagnostics: [SuiteDiagnostic],
    state: State,
    exitStatus: Int32 = 0
  ) -> AuthCommandResult<State> {
    AuthCommandResult(
      envelope: AuthEnvelope(
        operation: operation,
        outcome: outcome,
        changed: changed,
        diagnostics: diagnostics,
        state: state
      ),
      exitStatus: exitStatus
    )
  }
}
