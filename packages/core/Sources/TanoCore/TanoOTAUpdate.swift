import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// OTA Update system for Tano apps
/// Checks a remote manifest, downloads new bundles, and applies them on next launch
public final class TanoOTAUpdate {

    public struct Config {
        /// URL of the OTA update server manifest endpoint
        public var updateURL: String
        /// Current app version (bundle hash)
        public var currentHash: String
        /// Channel: "production", "staging", "canary"
        public var channel: String
        /// Directory to store downloaded updates
        public var updateDir: String
        /// Whether to check for updates automatically on launch
        public var autoCheck: Bool

        public init(updateURL: String, currentHash: String = "", channel: String = "production",
                     updateDir: String = "", autoCheck: Bool = true) {
            self.updateURL = updateURL
            self.currentHash = currentHash
            self.channel = channel
            self.updateDir = updateDir.isEmpty
                ? NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first! + "/tano-updates"
                : updateDir
            self.autoCheck = autoCheck
        }
    }

    public struct Manifest: Codable {
        public let version: String
        public let hash: String
        public let channel: String
        public let serverBundle: BundleInfo?
        public let webBundle: BundleInfo?
        public let createdAt: String

        public struct BundleInfo: Codable {
            public let url: String
            public let hash: String
            public let size: Int
        }
    }

    public enum UpdateStatus {
        case upToDate
        case available(Manifest)
        case downloading(Double) // progress 0.0-1.0
        case ready // downloaded, will apply on next launch
        case applying
        case failed(String)
    }

    private let config: Config
    private(set) var status: UpdateStatus = .upToDate

    public init(config: Config) {
        self.config = config
        // Create update directory
        try? FileManager.default.createDirectory(atPath: config.updateDir, withIntermediateDirectories: true)
    }

    // MARK: - Check for updates

    /// Check the update server for a new version
    public func checkForUpdate() async throws -> UpdateStatus {
        let url = URL(string: "\(config.updateURL)?channel=\(config.channel)&current=\(config.currentHash)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            status = .upToDate
            return status
        }

        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        if manifest.hash == config.currentHash {
            status = .upToDate
        } else {
            status = .available(manifest)
        }
        return status
    }

    // MARK: - Download update

    /// Download the update bundles
    public func downloadUpdate(manifest: Manifest) async throws {
        status = .downloading(0.0)

        let updatePath = (config.updateDir as NSString).appendingPathComponent(manifest.hash)
        try FileManager.default.createDirectory(atPath: updatePath, withIntermediateDirectories: true)

        // Download server bundle
        if let serverBundle = manifest.serverBundle {
            status = .downloading(0.2)
            let serverData = try await downloadFile(url: serverBundle.url)
            let serverPath = (updatePath as NSString).appendingPathComponent("server.js")
            try serverData.write(to: URL(fileURLWithPath: serverPath))

            // Verify hash
            let actualHash = sha256(data: serverData)
            if actualHash != serverBundle.hash {
                throw OTAError.hashMismatch(expected: serverBundle.hash, actual: actualHash)
            }
        }

        // Download web bundle
        if let webBundle = manifest.webBundle {
            status = .downloading(0.6)
            let webData = try await downloadFile(url: webBundle.url)
            let webPath = (updatePath as NSString).appendingPathComponent("web.zip")
            try webData.write(to: URL(fileURLWithPath: webPath))

            // Verify hash
            let actualHash = sha256(data: webData)
            if actualHash != webBundle.hash {
                throw OTAError.hashMismatch(expected: webBundle.hash, actual: actualHash)
            }

            // TODO: Unzip web bundle
        }

        // Write manifest
        status = .downloading(0.9)
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestPath = (updatePath as NSString).appendingPathComponent("manifest.json")
        try manifestData.write(to: URL(fileURLWithPath: manifestPath))

        // Mark as pending (will apply on next launch)
        let pendingPath = (config.updateDir as NSString).appendingPathComponent("pending")
        try manifest.hash.write(toFile: pendingPath, atomically: true, encoding: .utf8)

        status = .ready
    }

    // MARK: - Apply update

    /// Check if there's a pending update and return its paths
    /// Call this before starting the TanoRuntime to use the updated bundles
    public func pendingUpdate() -> (serverEntry: String, webDir: String)? {
        let pendingPath = (config.updateDir as NSString).appendingPathComponent("pending")
        guard let hash = try? String(contentsOfFile: pendingPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let updatePath = (config.updateDir as NSString).appendingPathComponent(hash)
        let serverPath = (updatePath as NSString).appendingPathComponent("server.js")
        let webPath = (updatePath as NSString).appendingPathComponent("web")

        guard FileManager.default.fileExists(atPath: serverPath) else {
            return nil
        }

        return (serverEntry: serverPath, webDir: webPath)
    }

    /// Mark the current update as successfully applied (prevents rollback)
    public func markApplied() {
        let pendingPath = (config.updateDir as NSString).appendingPathComponent("pending")
        guard let hash = try? String(contentsOfFile: pendingPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        // Move from pending to applied
        let appliedPath = (config.updateDir as NSString).appendingPathComponent("applied")
        try? hash.write(toFile: appliedPath, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: pendingPath)
    }

    /// Rollback: remove the pending update (e.g., if app crashes after update)
    public func rollback() {
        let pendingPath = (config.updateDir as NSString).appendingPathComponent("pending")
        guard let hash = try? String(contentsOfFile: pendingPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        let updatePath = (config.updateDir as NSString).appendingPathComponent(hash)
        try? FileManager.default.removeItem(atPath: updatePath)
        try? FileManager.default.removeItem(atPath: pendingPath)
    }

    /// Clean up old update bundles, keeping only the current one
    public func cleanup() {
        let appliedPath = (config.updateDir as NSString).appendingPathComponent("applied")
        let currentHash = (try? String(contentsOfFile: appliedPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: config.updateDir) else { return }
        for item in contents {
            if item == "pending" || item == "applied" || item == currentHash { continue }
            let itemPath = (config.updateDir as NSString).appendingPathComponent(item)
            try? FileManager.default.removeItem(atPath: itemPath)
        }
    }

    // MARK: - Helpers

    private func downloadFile(url: String) async throws -> Data {
        guard let fileURL = URL(string: url) else { throw OTAError.invalidURL(url) }
        let (data, _) = try await URLSession.shared.data(from: fileURL)
        return data
    }

    func sha256(data: Data) -> String {
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback: use the data count as a pseudo-hash (not secure, for structure only)
        return String(format: "%016x", data.count)
        #endif
    }
}

public enum OTAError: Error, LocalizedError {
    case invalidURL(String)
    case hashMismatch(expected: String, actual: String)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .hashMismatch(let expected, let actual): return "Hash mismatch: expected \(expected), got \(actual)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}
