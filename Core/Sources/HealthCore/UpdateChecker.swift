import Foundation
import CryptoKit

/// Pure update-check logic for the in-app update center (Build 26, P0).
/// No networking, no installation and no signing here: this file only
/// decodes and validates a manifest, decides whether it is newer than
/// the installed build, and verifies a downloaded artifact's SHA-256.
/// The iOS app layer (UpdateCenterStore) owns URLSession and the UI.
///
/// The production host allowlist is intentionally empty: no production
/// update source is configured yet. A production host is added only by
/// a separate, approved change; until then every remote manifest is
/// rejected as untrusted. The test fixture below is the only source
/// the update center can read in this build.
public enum UpdateChecker {
    /// No production update host is configured in this build.
    public static let productionTrustedHosts: Set<String> = []

    /// Decode + validate a manifest and decide against the installed build.
    public static func check(
        manifestData: Data,
        trustedHosts: Set<String>,
        installedBuild: Int
    ) throws -> (manifest: HealthUpdateManifest, decision: HealthUpdateManifest.UpdateDecision) {
        let manifest = try HealthUpdateManifest.decodeAndValidate(manifestData, trustedHosts: trustedHosts)
        return (manifest, manifest.decision(forInstalledBuild: installedBuild))
    }
}

public enum UpdateIntegrity {
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static func verify(data: Data, expectedSHA256: String) -> Bool {
        sha256Hex(of: data).lowercased() == expectedSHA256.lowercased()
    }
}

/// Test fixture for the update center. Test data only: the manifest
/// describes a fictitious build 999, its install page is the reserved
/// example.invalid host, and its artifact is a deterministic in-memory
/// payload. Nothing here is a production address, and no production
/// host is trusted by this fixture.
public enum UpdateTestFixture {
    public static let trustedHosts: Set<String> = ["example.invalid"]

    public static let artifactSHA256 = "1f5a16c4456f34c5459e4e66d8650d4dbb6b298810d0c21cef6571db21d69c81"

    public static var manifestJSON: Data {
        """
        {
          "schemaVersion": 1,
          "channel": "managed-ipa",
          "version": "9.9.9",
          "build": 999,
          "minimumSupportedBuild": 25,
          "releaseNotes": ["测试更新说明（测试数据，非正式发布）", "用于验证版本检查、下载、完整性校验与分享流程"],
          "publishedAt": "2026-11-26T00:00:00Z",
          "installPageURL": "https://example.invalid/updates",
          "artifactSHA256": "1f5a16c4456f34c5459e4e66d8650d4dbb6b298810d0c21cef6571db21d69c81"
        }
        """.data(using: .utf8)!
    }

    /// Deterministic 8 KiB payload: byte i is (i * 37 + 11) mod 256.
    /// Its SHA-256 is artifactSHA256 above (asserted by unit test).
    public static func artifactData() -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(8192)
        for i in 0..<8192 {
            bytes.append(UInt8((i * 37 + 11) % 256))
        }
        return Data(bytes)
    }
}
