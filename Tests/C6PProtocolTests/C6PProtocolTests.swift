import XCTest
@testable import C6PProtocol

/// Basic tests for C6P Protocol Swift Package
///
/// Note: These are minimal SPM integration tests.
/// Full protocol tests are in rust/c6p-ios/src/ (Rust test suite).
final class C6PProtocolTests: XCTestCase {

    func testVersionIsValid() {
        XCTAssertFalse(c6pVersion.isEmpty, "Version should not be empty")
        XCTAssertTrue(c6pVersion.contains("."), "Version should be in semver format")
    }

    func testMinimumIOSVersionIsValid() {
        XCTAssertEqual(c6pMinimumIOSVersion, "13.0", "Minimum iOS version should be 13.0")
    }

    // TODO: Add integration tests using actual C6P functions
    // once XCFramework is built and binary target is available
    //
    // Example:
    // func testGenerateIdentity() throws {
    //     let identity = try identity_generate_identity()
    //     XCTAssertFalse(identity.device_id.isEmpty)
    // }
}
