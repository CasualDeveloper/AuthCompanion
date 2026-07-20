import Darwin
import Foundation

public enum SystemToolError: Error, Equatable, CustomStringConvertible {
  case captureCreationFailed
  case outputTooLarge

  public var description: String {
    switch self {
    case .captureCreationFailed:
      "could not create a private command-output capture"
    case .outputTooLarge:
      "component command output exceeded the safety limit"
    }
  }
}

public final class SystemToolRunner: ToolRunning {
  private let maximumOutputBytes: UInt64

  public init(maximumOutputBytes: Int = 1_048_576) {
    self.maximumOutputBytes = UInt64(maximumOutputBytes)
  }

  public func run(_ invocation: ToolInvocation) throws -> ToolResult {
    let capture = try outputCapture()
    defer { try? capture.close() }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: invocation.executable)
    process.arguments = invocation.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = capture
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()

    let outputSize = try capture.seekToEnd()
    guard outputSize <= maximumOutputBytes else { throw SystemToolError.outputTooLarge }
    try capture.seek(toOffset: 0)
    let output = try capture.readToEnd() ?? Data()
    return ToolResult(
      exitStatus: process.terminationStatus,
      stdout: output,
      stderr: Data()
    )
  }

  private func outputCapture() throws -> FileHandle {
    let fileManager = FileManager.default
    let url = fileManager.temporaryDirectory
      .appendingPathComponent("authcompanion-output-\(UUID().uuidString)")
    guard
      fileManager.createFile(
        atPath: url.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
      )
    else {
      throw SystemToolError.captureCreationFailed
    }
    do {
      let handle = try FileHandle(forUpdating: url)
      try fileManager.removeItem(at: url)
      return handle
    } catch {
      try? fileManager.removeItem(at: url)
      throw error
    }
  }
}

public struct PAMSystemPaths: Equatable, Sendable {
  public let sudoLocal: String
  public let canonicalModule: String
  public let legacyModule: String
  public let versionedLegacyModule: String

  public init(
    sudoLocal: String,
    canonicalModule: String,
    legacyModule: String,
    versionedLegacyModule: String
  ) {
    self.sudoLocal = sudoLocal
    self.canonicalModule = canonicalModule
    self.legacyModule = legacyModule
    self.versionedLegacyModule = versionedLegacyModule
  }

  public static let system = PAMSystemPaths(
    sudoLocal: "/etc/pam.d/sudo_local",
    canonicalModule: "/usr/local/lib/pam/pam_companion.so",
    legacyModule: "/usr/local/lib/pam/pam_watchid.so",
    versionedLegacyModule: "/usr/local/lib/pam/pam_watchid.so.2"
  )
}

public enum PAMSnapshotReadError: Error, Equatable, CustomStringConvertible {
  case readFailed(String)
  case policyTooLarge

  public var description: String {
    switch self {
    case .readFailed(let path): "could not inspect \(path)"
    case .policyTooLarge: "sudo_local exceeded the 64 KiB inspection limit"
    }
  }
}

public final class FileSystemPAMSnapshotReader: PAMSnapshotReading {
  private let paths: PAMSystemPaths
  private let expectedOwnerUserID: uid_t
  private let maximumPolicyBytes = 65_536

  public init(
    paths: PAMSystemPaths = .system,
    expectedOwnerUserID: uid_t = 0
  ) {
    self.paths = paths
    self.expectedOwnerUserID = expectedOwnerUserID
  }

  public func read() throws -> PAMSnapshot {
    let policy = try readPolicy()
    let canonical = try inspectObject(at: paths.canonicalModule)
    let legacy = try inspectObject(at: paths.legacyModule)
    let versionedLegacy = try inspectObject(at: paths.versionedLegacyModule)
    return PAMSnapshot(
      sudoLocal: policy.data,
      canonicalModuleExists: canonical.exists,
      legacyModuleExists: legacy.exists,
      versionedLegacyModuleExists: versionedLegacy.exists,
      unsafeObjectExists: policy.unsafe || canonical.unsafe || legacy.unsafe
        || versionedLegacy.unsafe
    )
  }

  private func readPolicy() throws -> (data: Data, unsafe: Bool) {
    let status = try inspectObject(at: paths.sudoLocal)
    guard status.exists else { return (Data(), false) }
    guard !status.unsafe else { return (Data(), true) }

    let descriptor = open(paths.sudoLocal, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw PAMSnapshotReadError.readFailed(paths.sudoLocal) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, isSafe(metadata) else {
      return (Data(), true)
    }
    guard metadata.st_size <= maximumPolicyBytes else {
      throw PAMSnapshotReadError.policyTooLarge
    }
    return (try handle.readToEnd() ?? Data(), false)
  }

  private func inspectObject(at path: String) throws -> (exists: Bool, unsafe: Bool) {
    var metadata = stat()
    let status = path.withCString { lstat($0, &metadata) }
    if status != 0 {
      guard errno == ENOENT else { throw PAMSnapshotReadError.readFailed(path) }
      return (false, false)
    }
    return (true, !isSafe(metadata))
  }

  private func isSafe(_ metadata: stat) -> Bool {
    let isRegular = (metadata.st_mode & S_IFMT) == S_IFREG
    let isExpectedOwner = metadata.st_uid == expectedOwnerUserID
    let isNotGroupOrWorldWritable = metadata.st_mode & 0o022 == 0
    return isRegular && isExpectedOwner && isNotGroupOrWorldWritable
  }
}
