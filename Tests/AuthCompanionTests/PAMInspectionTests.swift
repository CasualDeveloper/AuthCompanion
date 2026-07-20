import XCTest

@testable import AuthCompanionCore

final class PAMInspectionTests: XCTestCase {
  func testRecognizesCanonicalConfigurationOnlyWhenModuleAndOrderAreCorrect() {
    let configured = PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_companion.so\nauth sufficient pam_tid.so\n".utf8),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
    XCTAssertEqual(PAMInspector.inspect(configured), .configured)

    let wrongOrder = PAMSnapshot(
      sudoLocal: Data("auth sufficient pam_tid.so\nauth sufficient pam_companion.so\n".utf8),
      canonicalModuleExists: true,
      legacyModuleExists: false,
      versionedLegacyModuleExists: false
    )
    XCTAssertEqual(PAMInspector.inspect(wrongOrder), .conflict)
  }

  func testClassifiesMissingLegacyUnmanagedAndConflictingStates() {
    XCTAssertEqual(
      PAMInspector.inspect(PAMSnapshot.empty),
      .notConfigured
    )
    XCTAssertEqual(
      PAMInspector.inspect(PAMSnapshot(
        sudoLocal: Data("auth sufficient pam_watchid.so.2\n".utf8),
        canonicalModuleExists: false,
        legacyModuleExists: false,
        versionedLegacyModuleExists: true
      )),
      .legacy
    )
    XCTAssertEqual(
      PAMInspector.inspect(PAMSnapshot(
        sudoLocal: Data(),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )),
      .unmanaged
    )
    XCTAssertEqual(
      PAMInspector.inspect(PAMSnapshot(
        sudoLocal: Data("auth sufficient pam_companion.so timeout=5\n".utf8),
        canonicalModuleExists: true,
        legacyModuleExists: false,
        versionedLegacyModuleExists: false
      )),
      .conflict
    )
  }

  func testCommentsAndSimilarNamesDoNotCountAsActiveModules() {
    let snapshot = PAMSnapshot(
      sudoLocal: Data("# auth sufficient pam_watchid.so.2\nauth sufficient pam_companion.so.backup\n".utf8),
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
}
