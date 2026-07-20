import Foundation

public enum PAMCondition: String, Codable, Equatable, Sendable {
  case configured
  case notConfigured
  case legacy
  case unmanaged
  case conflict
}

public struct PAMSnapshot: Equatable, Sendable {
  public let sudoLocal: Data
  public let canonicalModuleExists: Bool
  public let legacyModuleExists: Bool
  public let versionedLegacyModuleExists: Bool
  public let unsafeObjectExists: Bool

  public init(
    sudoLocal: Data,
    canonicalModuleExists: Bool,
    legacyModuleExists: Bool,
    versionedLegacyModuleExists: Bool,
    unsafeObjectExists: Bool = false
  ) {
    self.sudoLocal = sudoLocal
    self.canonicalModuleExists = canonicalModuleExists
    self.legacyModuleExists = legacyModuleExists
    self.versionedLegacyModuleExists = versionedLegacyModuleExists
    self.unsafeObjectExists = unsafeObjectExists
  }

  public static let empty = PAMSnapshot(
    sudoLocal: Data(),
    canonicalModuleExists: false,
    legacyModuleExists: false,
    versionedLegacyModuleExists: false,
    unsafeObjectExists: false
  )
}

public protocol PAMSnapshotReading: AnyObject {
  func read() throws -> PAMSnapshot
}

public enum PAMInspector {
  private static let canonical = "pam_companion.so"
  private static let legacy = Set(["pam_watchid.so", "pam_watchid.so.2"])

  public static func inspect(_ snapshot: PAMSnapshot) -> PAMCondition {
    guard !snapshot.unsafeObjectExists else { return .conflict }
    guard let policy = String(data: snapshot.sudoLocal, encoding: .utf8),
      !snapshot.sudoLocal.contains(0)
    else {
      return .conflict
    }

    let entries = policy.components(separatedBy: "\n").compactMap(activeTokens)
    guard entries.allSatisfy({ $0.count >= 3 }) else { return .conflict }
    let modules = entries.map { tokens in
      String(tokens[2].split(separator: "/").last ?? Substring(tokens[2]))
    }
    let canonicalIndexes = modules.indices.filter { modules[$0] == canonical }
    let legacyIndexes = modules.indices.filter { legacy.contains(modules[$0]) }
    let touchIDIndexes = modules.indices.filter { modules[$0] == "pam_tid.so" }
    let legacyReferenced = modules.contains(where: legacy.contains)
    let legacyExists = snapshot.legacyModuleExists || snapshot.versionedLegacyModuleExists

    guard canonicalIndexes.count + legacyIndexes.count <= 1,
      touchIDIndexes.count <= 1,
      modules.allSatisfy({ $0 == canonical || legacy.contains($0) || $0 == "pam_tid.so" })
    else {
      return .conflict
    }
    for index in canonicalIndexes + legacyIndexes {
      let tokens = entries[index]
      guard tokens[0] == "auth", tokens[1] == "sufficient",
        validArguments(Array(tokens.dropFirst(3)))
      else {
        return .conflict
      }
    }
    for index in touchIDIndexes {
      guard entries[index] == ["auth", "sufficient", "pam_tid.so"] else {
        return .conflict
      }
    }

    if !canonicalIndexes.isEmpty {
      guard canonicalIndexes.count == 1,
        !legacyReferenced,
        !legacyExists,
        snapshot.canonicalModuleExists
      else {
        return .conflict
      }
      let index = canonicalIndexes[0]
      if let touchIDIndex = modules.firstIndex(of: "pam_tid.so"), index > touchIDIndex {
        return .conflict
      }
      return .configured
    }

    if legacyReferenced || legacyExists { return .legacy }
    if snapshot.canonicalModuleExists { return .unmanaged }
    return .notConfigured
  }

  private static func activeTokens(_ line: String) -> [String]? {
    let tokens = line.prefix { $0 != "#" }.split(whereSeparator: { $0.isWhitespace }).map(
      String.init)
    return tokens.isEmpty ? nil : tokens
  }

  private static func validArguments(_ arguments: [String]) -> Bool {
    guard arguments.count <= 64 else { return false }
    var hasReason = false
    var hasTimeout = false
    for argument in arguments {
      guard let separator = argument.firstIndex(of: "=") else { return false }
      let name = String(argument[..<separator])
      let value = String(argument[argument.index(after: separator)...])
      switch name {
      case "reason":
        guard !hasReason, value.utf8.count <= 512,
          value.rangeOfCharacter(from: .controlCharacters) == nil
        else {
          return false
        }
        hasReason = true
      case "timeout":
        guard !hasTimeout, !value.isEmpty,
          value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
          let seconds = Int(value), (1...120).contains(seconds)
        else {
          return false
        }
        hasTimeout = true
      default:
        return false
      }
    }
    return true
  }
}

extension Data {
  fileprivate func contains(_ byte: UInt8) -> Bool {
    contains(where: { $0 == byte })
  }
}
