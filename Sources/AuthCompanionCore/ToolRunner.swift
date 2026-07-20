import Foundation

public struct ToolInvocation: Equatable, Sendable {
  public let executable: String
  public let arguments: [String]

  public init(executable: String, arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }
}

public struct ToolResult: Equatable, Sendable {
  public let exitStatus: Int32
  public let stdout: Data
  public let stderr: Data

  public init(exitStatus: Int32, stdout: Data, stderr: Data) {
    self.exitStatus = exitStatus
    self.stdout = stdout
    self.stderr = stderr
  }
}

public protocol ToolRunning: AnyObject {
  func run(_ invocation: ToolInvocation) throws -> ToolResult
}

public struct ComponentPaths: Equatable, Sendable {
  public let pinentryExecutable: String
  public let pamExecutable: String
  public let sudoExecutable: String

  public init(
    pinentryExecutable: String,
    pamExecutable: String,
    sudoExecutable: String
  ) {
    self.pinentryExecutable = pinentryExecutable
    self.pamExecutable = pamExecutable
    self.sudoExecutable = sudoExecutable
  }
}
