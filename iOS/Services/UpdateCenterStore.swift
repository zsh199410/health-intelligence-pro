import Foundation
import Combine
import HealthCore

/// Owns the update-center UI state (Build 26, P0). The only manifest
/// source in this build is the test fixture: no network, no production
/// host, no real installable artifact. Downloading means fetching the
/// fixture payload through a real URLSession byte stream and verifying
/// its SHA-256; sharing hands the verified file to the system share
/// sheet (LCsign is a share target there). This store never installs,
/// re-signs, or bypasses iOS signing.
@MainActor
final class UpdateCenterStore: ObservableObject {
    enum CheckState: Equatable {
        case idle
        case checking
        case upToDate(HealthUpdateManifest)
        case updateAvailable(HealthUpdateManifest)
        case failed(String)
    }

    enum DownloadState: Equatable {
        case idle
        case downloading(Double?)
        case verifying
        case verified(URL)
        case failed(String)
    }

    @Published private(set) var checkState: CheckState = .idle
    @Published private(set) var downloadState: DownloadState = .idle
    @Published private(set) var manifest: HealthUpdateManifest?
    @Published private(set) var isTestFixture = false
    @Published private(set) var lastCheckedAt: Date?

    private var lastCheckDate: Date?
    private var downloadTask: Task<Void, Never>?

    var installedBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var isChecking: Bool {
        if case .checking = checkState { return true }
        return false
    }

    /// Test-fixture check only in this build: no network, no production host.
    func checkUsingTestFixture() {
        guard !isChecking else { return }
        if let last = lastCheckDate, Date().timeIntervalSince(last) < 30 {
            checkState = .failed("检查过于频繁，请稍后再试。")
            return
        }
        lastCheckDate = Date()
        lastCheckedAt = Date()
        downloadState = .idle
        do {
            let (decoded, decision) = try UpdateChecker.check(
                manifestData: UpdateTestFixture.manifestJSON,
                trustedHosts: UpdateTestFixture.trustedHosts,
                installedBuild: installedBuild)
            manifest = decoded
            isTestFixture = true
            switch decision {
            case .upToDate:
                checkState = .upToDate(decoded)
            case .optionalUpdate:
                checkState = .updateAvailable(decoded)
            case .unsupportedInstalledBuild:
                checkState = .failed("当前安装版本过低，不支持此更新。请先安装受支持的版本。")
            }
        } catch {
            manifest = nil
            isTestFixture = false
            checkState = .failed("清单不可信：\(error.localizedDescription)")
        }
    }

    /// Downloads the test-fixture artifact through a real URLSession
    /// byte stream (from a local file URL), reports progress, then
    /// verifies SHA-256 against the manifest. Never installs anything.
    func downloadAndVerifyTestArtifact() {
        guard case .updateAvailable(let manifest) = checkState,
              isTestFixture, let expected = manifest.artifactSHA256 else { return }
        downloadTask?.cancel()
        downloadState = .downloading(nil)
        downloadTask = Task {
            do {
                let sourceURL = try writeFixturePayloadToTemporaryFile()
                let (bytes, response) = try await URLSession.shared.bytes(from: sourceURL)
                var data = Data()
                data.reserveCapacity(8192)
                let total = response.expectedContentLength
                var received: Int64 = 0
                var lastReported: Int64 = -1
                for try await byte in bytes {
                    data.append(byte)
                    received += 1
                    if total > 0, received - lastReported >= 1024 || received == total {
                        lastReported = received
                        downloadState = .downloading(Double(received) / Double(total))
                    }
                    try Task.checkCancellation()
                }
                guard !Task.isCancelled else { return }
                downloadState = .verifying
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("health-update-test-artifact.bin")
                try data.write(to: destination, options: .atomic)
                guard UpdateIntegrity.verify(data: data, expectedSHA256: expected) else {
                    downloadState = .failed("完整性校验失败：下载内容与清单摘要不一致，已拒绝使用。")
                    return
                }
                downloadState = .verified(destination)
            } catch is CancellationError {
                downloadState = .idle
            } catch {
                downloadState = .failed("下载失败：\(error.localizedDescription)")
            }
        }
    }

    func resetDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
        for name in ["health-update-test-source.bin", "health-update-test-artifact.bin"] {
            try? FileManager.default.removeItem(
                at: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        }
    }

    private func writeFixturePayloadToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-update-test-source.bin")
        try UpdateTestFixture.artifactData().write(to: url, options: .atomic)
        return url
    }
}
