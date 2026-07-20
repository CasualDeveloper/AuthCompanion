import Darwin
import Foundation
import XCTest

@testable import AuthCompanionCore

final class SystemToolRunnerTests: XCTestCase {
  func testRunsAnAbsoluteExecutableWithoutAShellAndCapturesStdout() throws {
    let result = try SystemToolRunner().run(
      ToolInvocation(
        executable: "/usr/bin/printf",
        arguments: ["%s", "hello"]
      ))

    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertEqual(result.stdout, Data("hello".utf8))
    XCTAssertTrue(result.stderr.isEmpty)
  }

  func testRejectsOutputBeyondTheConfiguredLimit() {
    XCTAssertThrowsError(
      try SystemToolRunner(maximumOutputBytes: 4).run(
        ToolInvocation(
          executable: "/usr/bin/printf",
          arguments: ["12345"]
        ))
    ) { error in
      XCTAssertEqual(error as? SystemToolError, .outputTooLarge)
    }
  }

  func testReportsChildExitStatus() throws {
    let result = try SystemToolRunner().run(
      ToolInvocation(executable: "/usr/bin/false", arguments: []))

    XCTAssertEqual(result.exitStatus, 1)
  }

  func testProvidesNoStandardInputToComponentCommands() throws {
    let result = try SystemToolRunner().run(
      ToolInvocation(executable: "/bin/cat", arguments: []))

    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertTrue(result.stdout.isEmpty)
  }
}

final class FileSystemPAMSnapshotReaderTests: XCTestCase {
  private var fixtureURL: URL!

  override func setUpWithError() throws {
    fixtureURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("authcompanion-pam-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: fixtureURL)
  }

  func testReadsAVisibleCanonicalPAMInstallation() throws {
    let paths = fixturePaths()
    try write(
      "auth sufficient pam_companion.so\nauth sufficient pam_tid.so\n",
      to: paths.sudoLocal
    )
    try write("module", to: paths.canonicalModule)

    let snapshot = try FileSystemPAMSnapshotReader(
      paths: paths,
      expectedOwnerUserID: getuid()
    ).read()

    XCTAssertEqual(PAMInspector.inspect(snapshot), .configured)
    XCTAssertFalse(snapshot.unsafeObjectExists)
  }

  func testMarksSymlinkedSystemObjectsUnsafe() throws {
    let paths = fixturePaths()
    try write("auth sufficient pam_companion.so\n", to: paths.sudoLocal)
    let outside = fixtureURL.appendingPathComponent("outside-module")
    try write("module", to: outside.path)
    try FileManager.default.createSymbolicLink(
      atPath: paths.canonicalModule,
      withDestinationPath: outside.path
    )

    let snapshot = try FileSystemPAMSnapshotReader(
      paths: paths,
      expectedOwnerUserID: getuid()
    ).read()

    XCTAssertTrue(snapshot.unsafeObjectExists)
    XCTAssertEqual(PAMInspector.inspect(snapshot), .conflict)
  }

  private func fixturePaths() -> PAMSystemPaths {
    PAMSystemPaths(
      sudoLocal: fixtureURL.appendingPathComponent("sudo_local").path,
      canonicalModule: fixtureURL.appendingPathComponent("pam_companion.so").path,
      legacyModule: fixtureURL.appendingPathComponent("pam_watchid.so").path,
      versionedLegacyModule: fixtureURL.appendingPathComponent("pam_watchid.so.2").path
    )
  }

  private func write(_ value: String, to path: String) throws {
    FileManager.default.createFile(atPath: path, contents: Data(value.utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
  }
}
