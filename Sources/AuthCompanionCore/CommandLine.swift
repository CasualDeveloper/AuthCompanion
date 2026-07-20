public enum OutputFormat: Equatable, Sendable {
  case human
  case json
}

public enum AuthCommand: Equatable, Sendable {
  case help
  case version
  case status(OutputFormat)
  case plan(OutputFormat)
  case setup(takeOver: Bool, format: OutputFormat)
  case restore(OutputFormat)
  case doctor(OutputFormat)
}

public enum AuthCommandLineError: Error, Equatable, CustomStringConvertible {
  case usage
  case confirmationRequired(String)

  public var description: String {
    switch self {
    case .usage:
      "usage: authcompanion <status|plan|setup|restore|doctor> [options]"
    case .confirmationRequired(let operation):
      "\(operation) requires explicit --yes confirmation"
    }
  }
}

public enum AuthCommandLine {
  public static func parse(_ arguments: [String]) throws -> AuthCommand {
    let values = Array(arguments.dropFirst())
    switch values {
    case ["help"], ["--help"], ["-h"]:
      return .help
    case ["--version"], ["version"]:
      return .version
    case ["status"]:
      return .status(.human)
    case ["status", "--format", "json"]:
      return .status(.json)
    case ["plan"]:
      return .plan(.human)
    case ["plan", "--format", "json"]:
      return .plan(.json)
    case ["doctor"]:
      return .doctor(.human)
    case ["doctor", "--format", "json"]:
      return .doctor(.json)
    case ["setup"]:
      throw AuthCommandLineError.confirmationRequired("setup")
    case ["setup", "--yes"]:
      return .setup(takeOver: false, format: .human)
    case ["setup", "--yes", "--format", "json"]:
      return .setup(takeOver: false, format: .json)
    case ["setup", "--yes", "--take-over"], ["setup", "--take-over", "--yes"]:
      return .setup(takeOver: true, format: .human)
    case ["setup", "--yes", "--take-over", "--format", "json"],
      ["setup", "--take-over", "--yes", "--format", "json"]:
      return .setup(takeOver: true, format: .json)
    case ["restore"]:
      throw AuthCommandLineError.confirmationRequired("restore")
    case ["restore", "--yes"]:
      return .restore(.human)
    case ["restore", "--yes", "--format", "json"]:
      return .restore(.json)
    default:
      throw AuthCommandLineError.usage
    }
  }
}
