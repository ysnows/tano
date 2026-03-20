import Foundation
import TanoBridge

/// Native file system plugin for Tano.
///
/// All paths are relative to a sandboxed `basePath` (typically the app's data directory).
/// Attempting to escape via `..` is rejected.
///
/// Supported methods: `read`, `write`, `exists`, `delete`, `list`, `mkdir`.
public final class FSPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "fs"
    public static let permissions: [String] = ["filesystem.app-data"]

    // MARK: - State

    private let basePath: String
    private let fileManager = FileManager.default

    /// Creates a new FSPlugin sandboxed to the given base directory.
    ///
    /// - Parameter basePath: The root directory for all file operations.
    public init(basePath: String) {
        self.basePath = basePath
    }

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "read":
            return try readFile(params: params)
        case "write":
            return try writeFile(params: params)
        case "exists":
            return try fileExists(params: params)
        case "delete":
            return try deleteFile(params: params)
        case "list":
            return try listDirectory(params: params)
        case "mkdir":
            return try makeDirectory(params: params)
        default:
            throw FSPluginError.unknownMethod(method)
        }
    }

    // MARK: - read

    private func readFile(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        guard fileManager.fileExists(atPath: fullPath) else {
            throw FSPluginError.fileNotFound(params["path"] as? String ?? "")
        }
        let content = try String(contentsOfFile: fullPath, encoding: .utf8)
        return ["content": content]
    }

    // MARK: - write

    private func writeFile(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        let content = params["content"] as? String ?? ""

        // Ensure parent directory exists
        let dir = (fullPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
        return ["success": true]
    }

    // MARK: - exists

    private func fileExists(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        let exists = fileManager.fileExists(atPath: fullPath)
        return ["exists": exists]
    }

    // MARK: - delete

    private func deleteFile(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        guard fileManager.fileExists(atPath: fullPath) else {
            throw FSPluginError.fileNotFound(params["path"] as? String ?? "")
        }
        try fileManager.removeItem(atPath: fullPath)
        return ["success": true]
    }

    // MARK: - list

    private func listDirectory(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
            throw FSPluginError.notADirectory(params["path"] as? String ?? "")
        }
        let entries = try fileManager.contentsOfDirectory(atPath: fullPath)
        return ["entries": entries.sorted()]
    }

    // MARK: - mkdir

    private func makeDirectory(params: [String: Any]) throws -> [String: Any] {
        let fullPath = try resolvePath(params)
        try fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
        return ["success": true]
    }

    // MARK: - Helpers

    /// Resolves a relative path against `basePath` and validates it stays within the sandbox.
    private func resolvePath(_ params: [String: Any]) throws -> String {
        guard let path = params["path"] as? String, !path.isEmpty else {
            throw FSPluginError.missingParameter("path")
        }

        let resolved = (basePath as NSString).appendingPathComponent(path)
        let canonical = (resolved as NSString).standardizingPath

        // Ensure the resolved path is still within basePath
        let canonicalBase = (basePath as NSString).standardizingPath
        guard canonical.hasPrefix(canonicalBase) else {
            throw FSPluginError.pathEscape(path)
        }

        return canonical
    }
}

// MARK: - Errors

public enum FSPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)
    case fileNotFound(String)
    case notADirectory(String)
    case pathEscape(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown fs plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .fileNotFound(let p):
            return "File not found: \(p)"
        case .notADirectory(let p):
            return "Not a directory: \(p)"
        case .pathEscape(let p):
            return "Path escapes sandbox: \(p)"
        }
    }
}
