import XCTest

@testable import AuthCompanionCore

final class PinentryContractTests: XCTestCase {
  func testRejectsSuccessEnvelopeWithFailureExitStatus() {
    let result = ToolResult(
      exitStatus: 1,
      stdout: pinentryStatusJSON(),
      stderr: Data()
    )

    XCTAssertThrowsError(try PinentryContractDecoder.status(result)) { error in
      XCTAssertEqual(error as? PinentryContractError, .mismatchedExitStatus)
    }
  }

  func testRejectsUnsupportedComponentVersion() {
    let result = ToolResult(
      exitStatus: 0,
      stdout: Data(
        pinentryStatusJSONText.replacingOccurrences(
          of: "\"componentVersion\":\"0.2.0\"",
          with: "\"componentVersion\":\"0.3.0\""
        ).utf8),
      stderr: Data()
    )

    XCTAssertThrowsError(try PinentryContractDecoder.status(result)) { error in
      XCTAssertEqual(error as? PinentryContractError, .invalidEnvelope)
    }
  }

  func testRejectsImpossibleMutationState() {
    let result = ToolResult(
      exitStatus: 0,
      stdout: pinentryMutationJSON(
        operation: "setup",
        changed: true,
        transactionState: "restored",
        safety: "compareAndSwapVerified"
      ),
      stderr: Data()
    )

    XCTAssertThrowsError(
      try PinentryContractDecoder.mutation(result, operation: "setup")
    ) { error in
      XCTAssertEqual(error as? PinentryContractError, .invalidEnvelope)
    }
  }

  func testRejectsPlanWhoseOutcomeContradictsItsState() {
    let inconsistent = String(decoding: pinentryPlanJSON(changeRequired: false), as: UTF8.self)
      .replacingOccurrences(of: "\"outcome\":\"ok\"", with: "\"outcome\":\"warning\"")
    let result = ToolResult(
      exitStatus: 0,
      stdout: Data(inconsistent.utf8),
      stderr: Data()
    )

    XCTAssertThrowsError(try PinentryContractDecoder.plan(result)) { error in
      XCTAssertEqual(error as? PinentryContractError, .invalidEnvelope)
    }
  }
}
