import XCTest

@testable import AuthCompanionCore

final class PinentryContractTests: XCTestCase {
  func testSupportedButUnexpectedVersionIsRejectedForEveryPinentryOperation() {
    let status = ToolResult(exitStatus: 0, stdout: pinentryStatusJSON(), stderr: Data())
    let plan = ToolResult(
      exitStatus: 0, stdout: pinentryPlanJSON(changeRequired: false), stderr: Data())
    let mutation = ToolResult(
      exitStatus: 0,
      stdout: pinentryMutationJSON(
        operation: "setup", changed: true, transactionState: "committed",
        safety: "exactRestoreStateRecorded"),
      stderr: Data()
    )

    XCTAssertThrowsError(try PinentryContractDecoder.status(status, expectedVersion: "0.2.1"))
    XCTAssertThrowsError(try PinentryContractDecoder.plan(plan, expectedVersion: "0.2.1"))
    XCTAssertThrowsError(
      try PinentryContractDecoder.mutation(mutation, operation: "setup", expectedVersion: "0.2.1")
    )
  }

  func testRejectsSuccessEnvelopeWithFailureExitStatus() {
    let result = ToolResult(
      exitStatus: 1,
      stdout: pinentryStatusJSON(),
      stderr: Data()
    )

    XCTAssertThrowsError(try PinentryContractDecoder.status(result, expectedVersion: "0.2.0")) {
      error in
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

    XCTAssertThrowsError(try PinentryContractDecoder.status(result, expectedVersion: "0.2.0")) {
      error in
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
      try PinentryContractDecoder.mutation(result, operation: "setup", expectedVersion: "0.2.0")
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

    XCTAssertThrowsError(try PinentryContractDecoder.plan(result, expectedVersion: "0.2.0")) {
      error in
      XCTAssertEqual(error as? PinentryContractError, .invalidEnvelope)
    }
  }
}
