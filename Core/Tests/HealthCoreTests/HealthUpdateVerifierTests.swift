import Foundation
import XCTest
@testable import HealthCore

#if canImport(CryptoKit)
import CryptoKit
#endif

final class HealthUpdateVerifierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func payload(build: Int, age: TimeInterval = 0, digest: String? = nil) throws -> Data {
        var json: [String: Any] = [
            "schemaVersion": 1, "channel": "managed-ipa", "version": "2.0.0", "build": build,
            "minimumSupportedBuild": 1, "releaseNotes": ["更新"], "installPageURL": "https://updates.example.org/a",
            "publishedAt": ISO8601DateFormatter().string(from: now.addingTimeInterval(-age))
        ]
        if let digest { json["artifactSHA256"] = digest }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    private func accept(_ build: Int, age: TimeInterval = 0, marker: UInt8 = 1,
                        channel: String = "managed-ipa", withDigest: Bool = true) async throws {
        let data = try payload(build: build, age: age, digest: withDigest ? String(repeating: "1", count: 64) : nil)
        let manifest = try HealthUpdateManifest.decodeAndValidate(data, trustedHosts: ["updates.example.org"])
        let ledger = HealthUpdateLedger(file: directory.appendingPathComponent("receipt"))
        try await ledger.accept(manifest, payloadDigest: Data([marker]), channel: channel, installedBuild: 22,
                                now: now, maximumAge: 86_400)
    }

    private func rejects(_ expected: HealthUpdateVerificationError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? HealthUpdateVerificationError, expected)
        }
    }

    func testPersistedFloorAndImmutablePublication() async throws {
        try await accept(23, age: 10)
        try await accept(23, age: 10)
        await rejects(.conflictingPublication) { try await self.accept(23, age: 10, marker: 2) }
        await rejects(.obsoleteBuild) { try await self.accept(22) }
        await rejects(.obsoleteBuild) { try await self.accept(24, age: 11) }
        try await accept(24)
        await rejects(.obsoleteBuild) { try await self.accept(23) }
    }

    func testFreshnessIdentityDigestAndInstalledFloor() async {
        await rejects(.outsidePublicationWindow) { try await self.accept(23, age: 86_401) }
        await rejects(.outsidePublicationWindow) { try await self.accept(23, age: -301) }
        await rejects(.wrongChannel) { try await self.accept(23, channel: "testflight") }
        await rejects(.missingArtifactDigest) { try await self.accept(23, withDigest: false) }
        await rejects(.obsoleteBuild) { try await self.accept(21) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("receipt").path))
    }

    func testCorruptReceiptCannotSilentlyResetFloor() async throws {
        let file = directory.appendingPathComponent("receipt")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: file)
        do {
            try await accept(23)
            XCTFail("Expected a decoding failure")
        } catch is DecodingError {}
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    #if canImport(CryptoKit)
    @available(macOS 11, *)
    func testDetachedSignatureAndArtifactDigest() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let receipt = directory.appendingPathComponent("receipt")
        let verifier = try HealthUpdateVerifier(pinnedPublicKey: key.publicKey.rawRepresentation,
            channel: "managed-ipa", trustedHosts: ["updates.example.org"], ledgerFile: receipt, maximumAge: 86_400)
        let bytes = Data("abc".utf8)
        let data = try payload(build: 23, digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let signature = try key.signature(for: data)
        await rejects(.invalidSignature) {
            _ = try await verifier.verify(payload: data + Data(" ".utf8), detachedSignature: signature, installedBuild: 22, now: self.now)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        let result = try await verifier.verify(payload: data, detachedSignature: signature, installedBuild: 22, now: now)
        let file = directory.appendingPathComponent("fixture.ipa")
        try bytes.write(to: file)
        try result.verifyArtifact(at: file)
        try Data("abd".utf8).write(to: file)
        XCTAssertThrowsError(try result.verifyArtifact(at: file)) {
            XCTAssertEqual($0 as? HealthUpdateVerificationError, .artifactMismatch)
        }
    }
    #endif
}
