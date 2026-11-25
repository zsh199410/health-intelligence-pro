import Foundation

public enum HealthUpdateVerificationError: Error, Equatable {
    case invalidSignature
    case invalidSize
    case wrongChannel
    case invalidFreshnessPolicy
    case outsidePublicationWindow
    case obsoleteBuild
    case conflictingPublication
    case missingArtifactDigest
    case artifactMismatch
}

/// Use one ledger per app and distribution channel in application support storage.
actor HealthUpdateLedger {
    private struct Receipt: Codable {
        let channel: String
        let build: Int
        let publishedAt: Date
        let payloadDigest: Data
    }

    private let file: URL

    init(file: URL) {
        self.file = file
    }

    func accept(_ manifest: HealthUpdateManifest, payloadDigest: Data, channel: String,
                installedBuild: Int, now: Date, maximumAge: TimeInterval) throws {
        guard manifest.channel == channel else { throw HealthUpdateVerificationError.wrongChannel }
        guard maximumAge.isFinite, maximumAge > 0 else { throw HealthUpdateVerificationError.invalidFreshnessPolicy }
        let age = now.timeIntervalSince(manifest.publishedAt)
        guard (-300...maximumAge).contains(age) else { throw HealthUpdateVerificationError.outsidePublicationWindow }
        guard installedBuild > 0, manifest.build >= installedBuild else { throw HealthUpdateVerificationError.obsoleteBuild }
        if channel == "managed-ipa", manifest.artifactSHA256 == nil {
            throw HealthUpdateVerificationError.missingArtifactDigest
        }

        let previous: Receipt?
        do {
            previous = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            previous = nil
        }

        if let previous {
            guard previous.channel == channel else { throw HealthUpdateVerificationError.wrongChannel }
            guard manifest.build >= previous.build,
                  manifest.publishedAt >= previous.publishedAt else { throw HealthUpdateVerificationError.obsoleteBuild }
            if manifest.build == previous.build {
                guard previous.payloadDigest == payloadDigest else { throw HealthUpdateVerificationError.conflictingPublication }
                return
            }
        }
        let next = Receipt(channel: channel, build: manifest.build, publishedAt: manifest.publishedAt,
                           payloadDigest: payloadDigest)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
    }
}

#if canImport(CryptoKit)
import CryptoKit

/// The caller supplies a release verification key pinned in the app for this feed.
@available(macOS 11, *)
public struct HealthUpdateVerifier {
    private let key: Curve25519.Signing.PublicKey
    private let ledger: HealthUpdateLedger
    private let trustedHosts: Set<String>
    private let channel: String
    private let maximumAge: TimeInterval

    public init(pinnedPublicKey: Data, channel: String, trustedHosts: Set<String>,
                ledgerFile: URL, maximumAge: TimeInterval) throws {
        key = try Curve25519.Signing.PublicKey(rawRepresentation: pinnedPublicKey)
        self.ledger = HealthUpdateLedger(file: ledgerFile)
        self.channel = channel
        self.trustedHosts = trustedHosts
        self.maximumAge = maximumAge
    }

    /// Ed25519 covers the exact JSON bytes. Persist the receipt before returning an update.
    public func verify(payload: Data, detachedSignature: Data, installedBuild: Int,
                       now: Date = Date()) async throws -> VerifiedHealthUpdate {
        guard !payload.isEmpty, payload.count <= 65_536 else { throw HealthUpdateVerificationError.invalidSize }
        guard key.isValidSignature(detachedSignature, for: payload) else { throw HealthUpdateVerificationError.invalidSignature }
        let manifest = try HealthUpdateManifest.decodeAndValidate(payload, trustedHosts: trustedHosts)
        try await ledger.accept(manifest, payloadDigest: Data(SHA256.hash(data: payload)), channel: channel,
                                installedBuild: installedBuild, now: now, maximumAge: maximumAge)
        return VerifiedHealthUpdate(manifest: manifest)
    }
}

@available(macOS 11, *)
public struct VerifiedHealthUpdate {
    public let manifest: HealthUpdateManifest
    fileprivate init(manifest: HealthUpdateManifest) { self.manifest = manifest }

    /// Check the downloaded bytes in a private staging file before making the IPA available.
    public func verifyArtifact(at url: URL) throws {
        guard let expected = manifest.artifactSHA256 else { throw HealthUpdateVerificationError.missingArtifactDigest }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected.lowercased() else { throw HealthUpdateVerificationError.artifactMismatch }
    }
}
#endif
