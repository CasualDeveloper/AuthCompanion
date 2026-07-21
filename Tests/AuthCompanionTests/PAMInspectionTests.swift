import XCTest

@testable import AuthCompanionCore

final class PAMInspectionTests: XCTestCase {
  func testRecognizesNativeTouchIDConfiguration() {
    let configured = PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_tid.so\n".utf8),
      canonicalModuleExists: false,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
    XCTAssertEqual(PAMInspector.inspect(configured), .configured)
  }

  func testClassifiesMissingLegacyUnmanagedAndConflictingStates() {
    XCTAssertEqual(
      PAMInspector.inspect(PAMSnapshot.empty),
      .notConfigured
    )
    XCTAssertEqual(
      PAMInspector.inspect(
        PAMSnapshot(
          sudoLocal: Data("auth sufficient pam_watchid.so.2\n".utf8),
          canonicalModuleExists: false,
          legacyModuleExists: false,
          versionedLegacyModuleExists: true
        )),
      .legacy
    )
    XCTAssertEqual(
      PAMInspector.inspect(
        PAMSnapshot(
          sudoLocal: Data(),
          canonicalModuleExists: true,
          legacyModuleExists: false,
          versionedLegacyModuleExists: false
        )),
      .legacy
    )
    XCTAssertEqual(
      PAMInspector.inspect(
        PAMSnapshot(
          sudoLocal: Data("auth required pam_companion.so\n".utf8),
          canonicalModuleExists: true,
          legacyModuleExists: false,
          versionedLegacyModuleExists: false
        )),
      .conflict
    )
  }

  func testCommentsAndSimilarNamesDoNotCountAsActiveModules() {
    let snapshot = PAMSnapshot(
      sudoLocal: Data(
        "# auth sufficient pam_watchid.so.2\nauth sufficient pam_companion.so.backup\n".utf8),
      canonicalModuleExists: false,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
    XCTAssertEqual(PAMInspector.inspect(snapshot), .conflict)
  }

  func testMalformedActivePolicyLineFailsClosed() {
    let snapshot = PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_companion.so\nauth\n".utf8),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )

    XCTAssertEqual(PAMInspector.inspect(snapshot), .conflict)
  }

  func testUnsafeFilesystemObjectFailsClosed() {
    let snapshot = PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_companion.so\n".utf8),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false,
      unsafeObjectExists: true
    )

    XCTAssertEqual(PAMInspector.inspect(snapshot), .conflict)
  }

  func testClassifiesCustomModuleConfigurationAndArgumentsAsLegacy() {
    let snapshot = PAMSnapshot(
      sudoLocal: Data(
        "auth sufficient pam_companion.so old-option arbitrary=value\nauth sufficient pam_tid.so\n"
          .utf8
      ),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )

    XCTAssertEqual(PAMInspector.inspect(snapshot), .legacy)
  }

  func testRejectsDuplicateModulesAndUnrelatedActiveModules() {
    for policy in [
      "auth sufficient pam_companion.so\nauth sufficient pam_tid.so\nauth sufficient pam_tid.so\n",
      "auth sufficient pam_companion.so\nauth sufficient pam_watchid.so\n",
      "auth sufficient pam_companion.so\nauth required pam_opendirectory.so\n",
    ] {
      let snapshot = PAMSnapshot(
        sudoLocal: Data(policy.utf8),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )

      XCTAssertEqual(PAMInspector.inspect(snapshot), .conflict, policy)
    }
  }
}
