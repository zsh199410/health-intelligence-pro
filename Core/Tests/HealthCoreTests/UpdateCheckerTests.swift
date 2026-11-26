import Foundation
import XCTest
@testable import HealthCore

final class UpdateCheckerTests: XCTestCase {
    func testFixtureDecodesAndDecidesOptionalUpdate() throws {
        let (manifest, decision) = try UpdateChecker.check(
            manifestData: UpdateTestFixture.manifestJSON,
            trustedHosts: UpdateTestFixture.trustedHosts,
            installedBuild: 25)
        XCTAssertEqual(manifest.version, "9.9.9")
        XCTAssertEqual(manifest.build, 999)
        XCTAssertEqual(manifest.channel, "managed-ipa")
        XCTAssertEqual(decision, .optionalUpdate)
    }

    func testFixtureDecisionAcrossInstalledBuilds() throws {
        let manifest = try HealthUpdateManifest.decodeAndValidate(
            UpdateTestFixture.manifestJSON, trustedHosts: UpdateTestFixture.trustedHosts)
        XCTAssertEqual(manifest.decision(forInstalledBuild: 999), .upToDate)
        XCTAssertEqual(manifest.decision(forInstalledBuild: 1000), .upToDate)
        XCTAssertEqual(manifest.decision(forInstalledBuild: 24), .unsupportedInstalledBuild)
        XCTAssertEqual(manifest.decision(forInstalledBuild: 0), .unsupportedInstalledBuild)
    }

    func testFixtureRejectedByProductionHosts() {
        XCTAssertThrowsError(try UpdateChecker.check(
            manifestData: UpdateTestFixture.manifestJSON,
            trustedHosts: UpdateChecker.productionTrustedHosts,
            installedBuild: 25))
        XCTAssertTrue(UpdateChecker.productionTrustedHosts.isEmpty)
    }

    func testFixtureArtifactSHA256Matches() {
        let data = UpdateTestFixture.artifactData()
        XCTAssertEqual(data.count, 8192)
        XCTAssertEqual(UpdateIntegrity.sha256Hex(of: data), UpdateTestFixture.artifactSHA256)
        XCTAssertTrue(UpdateIntegrity.verify(data: data, expectedSHA256: UpdateTestFixture.artifactSHA256))
    }

    func testIntegrityRejectsTamperedData() {
        var data = UpdateTestFixture.artifactData()
        data[0] ^= 0xFF
        XCTAssertFalse(UpdateIntegrity.verify(data: data, expectedSHA256: UpdateTestFixture.artifactSHA256))
        XCTAssertFalse(UpdateIntegrity.verify(data: UpdateTestFixture.artifactData(), expectedSHA256: String(repeating: "0", count: 64)))
    }

    func testSHA256KnownVector() {
        XCTAssertEqual(
            UpdateIntegrity.sha256Hex(of: Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testCheckRejectsMalformedJSON() {
        XCTAssertThrowsError(try UpdateChecker.check(
            manifestData: Data("not json".utf8),
            trustedHosts: UpdateTestFixture.trustedHosts,
            installedBuild: 25))
    }

    func testCheckRejectsUntrustedHost() {
        let tampered = UpdateTestFixture.manifestJSON
        let text = String(decoding: tampered, as: UTF8.self)
            .replacingOccurrences(of: "example.invalid", with: "evil.test")
        XCTAssertThrowsError(try UpdateChecker.check(
            manifestData: Data(text.utf8),
            trustedHosts: UpdateTestFixture.trustedHosts,
            installedBuild: 25))
    }
}
