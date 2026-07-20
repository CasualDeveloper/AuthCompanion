import XCTest

@testable import AuthCompanionCore

final class CommandLineTests: XCTestCase {
  func testParsesPassiveCommandsAndOutputFormat() throws {
    XCTAssertEqual(try AuthCommandLine.parse(["authcompanion", "status"]), .status(.human))
    XCTAssertEqual(
      try AuthCommandLine.parse(["authcompanion", "plan", "--format", "json"]),
      .plan(.json)
    )
    XCTAssertEqual(
      try AuthCommandLine.parse(["authcompanion", "doctor", "--format", "json"]),
      .doctor(.json)
    )
  }

  func testMutationsRequireExactConfirmationAndOptionScope() throws {
    XCTAssertEqual(
      try AuthCommandLine.parse(["authcompanion", "setup", "--yes"]),
      .setup(takeOver: false, format: .human)
    )
    XCTAssertEqual(
      try AuthCommandLine.parse([
        "authcompanion", "setup", "--yes", "--take-over", "--format", "json",
      ]),
      .setup(takeOver: true, format: .json)
    )
    XCTAssertEqual(
      try AuthCommandLine.parse(["authcompanion", "restore", "--yes", "--format", "json"]),
      .restore(.json)
    )

    for arguments in [
      ["authcompanion", "setup"],
      ["authcompanion", "restore"],
      ["authcompanion", "restore", "--yes", "--take-over"],
      ["authcompanion", "status", "--yes"],
      ["authcompanion", "unknown"],
    ] {
      XCTAssertThrowsError(try AuthCommandLine.parse(arguments), "\(arguments)")
    }
  }

  func testHelpAndVersionRemainUnprivileged() throws {
    XCTAssertEqual(try AuthCommandLine.parse(["authcompanion", "--help"]), .help)
    XCTAssertEqual(try AuthCommandLine.parse(["authcompanion", "-h"]), .help)
    XCTAssertEqual(try AuthCommandLine.parse(["authcompanion", "--version"]), .version)
  }
}
