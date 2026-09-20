import Foundation
import XCTest

@testable import AuthCompanionCore

final class ProducerFixtureTests: XCTestCase {
  func testAcceptsPublishedAndCandidatePinentryFixtures() throws {
    let common = [
      "status/configured.json", "plan/no-change.json", "plan/foreign-conflict.json",
      "lifecycle/setup-changed.json", "lifecycle/setup-unchanged.json",
      "lifecycle/restore-restored.json", "lifecycle/setup-rollback-failed.json",
      "lifecycle/setup-indeterminate.json",
    ]
    let candidateOnly = [
      "lifecycle/setup-ownership-recorded.json", "lifecycle/setup-recovered.json",
    ]
    for version in ["0.2.0", "0.2.1"] {
      let root = try XCTUnwrap(Bundle.module.resourceURL)
        .appendingPathComponent("Fixtures/pinentry/\(version)")
      for name in common + (version == "0.2.1" ? candidateOnly : []) {
        let data = try Data(contentsOf: root.appendingPathComponent(name))
        let header = try JSONDecoder().decode(Header.self, from: data)
        XCTAssertEqual(header.componentVersion, version, name)
        let succeeded = header.outcome == .ok || header.outcome == .warning
        let result = ToolResult(exitStatus: succeeded ? 0 : 1, stdout: data, stderr: Data())
        switch header.operation {
        case "status":
          XCTAssertNoThrow(try PinentryContractDecoder.status(result, expectedVersion: version))
        case "plan":
          XCTAssertNoThrow(try PinentryContractDecoder.plan(result, expectedVersion: version))
        case "setup", "restore":
          XCTAssertNoThrow(
            try PinentryContractDecoder.mutation(
              result, operation: header.operation, expectedVersion: version))
        default:
          XCTFail("Unexpected producer fixture operation: \(header.operation)")
        }
      }
    }
  }

  private struct Header: Decodable {
    let componentVersion: String
    let operation: String
    let outcome: SuiteOutcome
  }
}
