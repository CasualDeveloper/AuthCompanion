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
    let removableReferenced = !canonicalIndexes.isEmpty || !legacyIndexes.isEmpty
    let removableExists =
      snapshot.canonicalModuleExists || snapshot.legacyModuleExists
      || snapshot.versionedLegacyModuleExists

    guard canonicalIndexes.count + legacyIndexes.count <= 1,
      touchIDIndexes.count <= 1,
      modules.allSatisfy({ $0 == canonical || legacy.contains($0) || $0 == "pam_tid.so" })
    else {
      return .conflict
    }
    for index in canonicalIndexes + legacyIndexes {
      let tokens = entries[index]
      guard tokens[0] == "auth", tokens[1] == "sufficient" else {
        return .conflict
      }
    }
    for index in touchIDIndexes {
      guard entries[index] == ["auth", "sufficient", "pam_tid.so"] else {
        return .conflict
      }
    }

    if removableReferenced || removableExists { return .legacy }
    if touchIDIndexes.count == 1 { return .configured }
    return .notConfigured
  }

  private static func activeTokens(_ line: String) -> [String]? {
    let tokens = line.prefix { $0 != "#" }.split(whereSeparator: { $0.isWhitespace }).map(
      String.init)
    return tokens.isEmpty ? nil : tokens
  }

}

extension Data {
  fileprivate func contains(_ byte: UInt8) -> Bool {
    contains(where: { $0 == byte })
  }
}
