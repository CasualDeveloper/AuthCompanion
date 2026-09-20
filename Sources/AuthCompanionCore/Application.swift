import Foundation

public struct ApplicationOutput: Equatable, Sendable {
  public let exitStatus: Int32
  public let stdout: String
  public let stderr: String

  public init(exitStatus: Int32, stdout: String = "", stderr: String = "") {
    self.exitStatus = exitStatus
    self.stdout = stdout
    self.stderr = stderr
  }
}

public final class AuthCompanionApplication {
  private let effectiveUserID: UInt32
  private let locator: any ComponentLocating
  private let runner: any ToolRunning
  private let pamSnapshots: any PAMSnapshotReading

  public init(
    effectiveUserID: UInt32,
    locator: any ComponentLocating,
    runner: any ToolRunning,
    pamSnapshots: any PAMSnapshotReading
  ) {
    self.effectiveUserID = effectiveUserID
    self.locator = locator
    self.runner = runner
    self.pamSnapshots = pamSnapshots
  }

  public static func live(effectiveUserID: UInt32) -> AuthCompanionApplication {
    let runner = SystemToolRunner()
    return AuthCompanionApplication(
      effectiveUserID: effectiveUserID,
      locator: HomebrewComponentLocator(),
      runner: runner,
      pamSnapshots: FileSystemPAMSnapshotReader()
    )
  }

  public func run(_ arguments: [String]) -> ApplicationOutput {
    let command: AuthCommand
    do {
      command = try AuthCommandLine.parse(arguments)
    } catch {
      return ApplicationOutput(
        exitStatus: 2,
        stderr: "authcompanion: \(error)\n"
      )
    }

    switch command {
    case .help:
      return ApplicationOutput(exitStatus: 0, stdout: AuthOutputRenderer.help + "\n")
    case .version:
      return ApplicationOutput(
        exitStatus: 0,
        stdout: "authcompanion \(AuthCompanionVersion.current)\n"
      )
    default:
      break
    }

    guard effectiveUserID != 0 else {
      return failure(
        command: command,
        code: "invocation.rootForbidden",
        message: "Do not run AuthCompanion itself with sudo.",
        remediation: "Run the same authcompanion command as your login user."
      )
    }

    let paths: ComponentPaths
    let versions: ComponentVersions
    do {
      paths = try locator.locate()
      versions = try ComponentVersionVerifier.verify(paths: paths, runner: runner)
    } catch {
      return failure(
        command: command,
        code: "dependency.unavailable",
        message: String(describing: error),
        remediation: dependencyRemediation(error)
      )
    }

    if requiresAdministratorAuthorization(command) {
      do {
        let authorization = try runner.run(
          ToolInvocation(
            executable: paths.sudoExecutable,
            arguments: ["-n", "--", "/usr/bin/true"]
          ))
        guard authorization.exitStatus == 0 else {
          return authorizationRequired(command: command)
        }
      } catch {
        return authorizationRequired(command: command)
      }
    }

    let manager = AuthCompanionManager(
      paths: paths,
      versions: versions,
      runner: runner,
      pamSnapshots: pamSnapshots
    )
    switch command {
    case .status(let format):
      let result = manager.status()
      return render(result, format: format, human: AuthOutputRenderer.status(result))
    case .plan(let format):
      let result = manager.plan()
      return render(result, format: format, human: AuthOutputRenderer.plan(result))
    case .setup(let takeOver, let format):
      let result = manager.setup(takeOver: takeOver)
      return render(
        result,
        format: format,
        human: AuthOutputRenderer.mutation(result, operation: "setup")
      )
    case .restore(let format):
      let result = manager.restore()
      return render(
        result,
        format: format,
        human: AuthOutputRenderer.mutation(result, operation: "restore")
      )
    case .doctor(let format):
      let result = manager.doctor()
      return render(result, format: format, human: AuthOutputRenderer.doctor(result))
    case .help, .version:
      return ApplicationOutput(exitStatus: 0)
    }
  }

  private func requiresAdministratorAuthorization(_ command: AuthCommand) -> Bool {
    switch command {
    case .setup, .restore, .doctor:
      true
    case .status, .plan, .help, .version:
      false
    }
  }

  private func dependencyRemediation(_ error: any Error) -> String {
    if case DependencyError.unsupportedVersion = error {
      return "Upgrade authcompanion to a release supporting the installed components, then retry."
    }
    return
      "Run `brew install casualdeveloper/tap/pinentry-companion casualdeveloper/tap/pam-companion`, then retry."
  }

  private func authorizationRequired(command: AuthCommand) -> ApplicationOutput {
    failure(
      command: command,
      code: "sudo.authorizationRequired",
      message: "Administrator authorization is required before this command can run.",
      remediation: "Run `sudo -v`, then rerun the same authcompanion command."
    )
  }

  private func render<State: Codable & Equatable & Sendable>(
    _ result: AuthCommandResult<State>,
    format: OutputFormat,
    human: String
  ) -> ApplicationOutput {
    switch format {
    case .json:
      do {
        return ApplicationOutput(
          exitStatus: result.exitStatus,
          stdout: try AuthOutputRenderer.json(result.envelope) + "\n"
        )
      } catch {
        return ApplicationOutput(
          exitStatus: 1,
          stderr: "authcompanion: could not encode the JSON response\n"
        )
      }
    case .human:
      if result.exitStatus == 0 {
        return ApplicationOutput(exitStatus: 0, stdout: human + "\n")
      }
      return ApplicationOutput(exitStatus: result.exitStatus, stderr: human + "\n")
    }
  }

  private func failure(
    command: AuthCommand,
    code: String,
    message: String,
    remediation: String
  ) -> ApplicationOutput {
    let diagnostic = SuiteDiagnostic(
      code: code,
      severity: .error,
      message: message,
      remediation: remediation
    )
    guard outputFormat(command) == .json else {
      return ApplicationOutput(
        exitStatus: 1,
        stderr: "authcompanion: \(message)\nFix: \(remediation)\n"
      )
    }
    let envelope = AuthEnvelope(
      operation: operation(command),
      outcome: .error,
      changed: false,
      diagnostics: [diagnostic],
      state: FailureState(reason: code)
    )
    do {
      return ApplicationOutput(
        exitStatus: 1,
        stdout: try AuthOutputRenderer.json(envelope) + "\n"
      )
    } catch {
      return ApplicationOutput(
        exitStatus: 1,
        stderr: "authcompanion: could not encode the JSON response\n"
      )
    }
  }

  private func outputFormat(_ command: AuthCommand) -> OutputFormat? {
    switch command {
    case .status(let format), .plan(let format), .restore(let format), .doctor(let format):
      format
    case .setup(_, let format):
      format
    case .help, .version:
      nil
    }
  }

  private func operation(_ command: AuthCommand) -> String {
    switch command {
    case .status: "status"
    case .plan: "plan"
    case .setup: "setup"
    case .restore: "restore"
    case .doctor: "doctor"
    case .help: "help"
    case .version: "version"
    }
  }
}
