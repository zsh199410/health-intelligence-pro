import Foundation

/// A metadata-only update feed. Never downloads or installs an IPA.
public struct HealthUpdateManifest: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let channel: String
    public let version: String
    public let build: Int
    public let minimumSupportedBuild: Int
    public let releaseNotes: [String]
    public let publishedAt: Date
    public let installPageURL: URL
    public let artifactSHA256: String?

    public enum ValidationError: Error, Equatable {
        case unsupportedSchema
        case unsupportedChannel
        case invalidBuild
        case invalidVersion
        case invalidReleaseNotes
        case untrustedInstallURL
        case invalidArtifactDigest
    }

    /// Validation must happen before presenting an external update link.
    /// trustedHosts is an explicit app-controlled allowlist, not a feed field.
    public func validate(trustedHosts: Set<String>) throws {
        guard schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        guard channel == "testflight" || channel == "managed-ipa" else {
            throw ValidationError.unsupportedChannel
        }
        guard build > 0, minimumSupportedBuild > 0,
              minimumSupportedBuild <= build else { throw ValidationError.invalidBuild }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) &&
                  $0.allSatisfy(\.isNumber) && Int($0) != nil }) else {
            throw ValidationError.invalidVersion
        }
        guard !releaseNotes.isEmpty, releaseNotes.count <= 20,
              releaseNotes.allSatisfy({ note in
                  !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  note.count <= 500 &&
                  !note.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }) else {
            throw ValidationError.invalidReleaseNotes
        }
        guard installPageURL.scheme?.lowercased() == "https",
              installPageURL.user == nil, installPageURL.password == nil,
              installPageURL.port == nil, installPageURL.fragment == nil,
              let host = installPageURL.host?.lowercased(),
              trustedHosts.contains(host) else {
            throw ValidationError.untrustedInstallURL
        }
        if let digest = artifactSHA256 {
            guard digest.count == 64,
                  digest.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                throw ValidationError.invalidArtifactDigest
            }
        }
    }

    public static func decodeAndValidate(_ data: Data, trustedHosts: Set<String>) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Self.self, from: data)
        try manifest.validate(trustedHosts: trustedHosts)
        return manifest
    }

    /// Advisory only: the approved distribution channel performs installation.
    public enum UpdateDecision: Equatable, Sendable {
        case upToDate
        case optionalUpdate
        case unsupportedInstalledBuild
    }

    public func decision(forInstalledBuild installedBuild: Int) -> UpdateDecision {
        guard installedBuild > 0 else { return .unsupportedInstalledBuild }
        if installedBuild < minimumSupportedBuild { return .unsupportedInstalledBuild }
        return build > installedBuild ? .optionalUpdate : .upToDate
    }

    public func isNewer(thanInstalledBuild installedBuild: Int) -> Bool {
        build > installedBuild
    }
}
