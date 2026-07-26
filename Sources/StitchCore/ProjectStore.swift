import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum StoreError: Error, Equatable {
    case corruptedAndNoBackup(underlying: String)
    case notWritable(path: String)
}

/// Result of a load, including whether recovery was needed. The UI surfaces this so a
/// knitter is told "restored from backup" rather than silently seeing stale counts.
public struct LoadResult: Sendable, Equatable {
    public let projects: [Project]
    public let recoveredFromBackup: Bool

    public init(projects: [Project], recoveredFromBackup: Bool) {
        self.projects = projects
        self.recoveredFromBackup = recoveredFromBackup
    }
}

public protocol ProjectStoring: Sendable {
    func load() throws -> LoadResult
    func save(_ projects: [Project]) throws
}

/// File-backed store with atomic writes and a one-generation backup.
///
/// The competitor complaint this exists to prevent is "my pattern disappeared". Three
/// properties defend against it:
///
/// 1. Writes go to a temp file which is fsynced, then `rename`d over the live file.
///    `rename` is atomic on POSIX, so a crash or battery death mid-save leaves either the
///    complete old file or the complete new one — never a truncated one.
/// 2. The previous good file is copied to a backup before each write, so even a logically
///    bad save (rather than a torn one) is recoverable.
/// 3. Load falls back to the backup on any decode failure and reports that it did.
public struct FileProjectStore: ProjectStoring {
    public static let schemaVersion = 1

    public let directory: URL

    private var liveURL: URL { directory.appendingPathComponent("projects.json") }
    private var backupURL: URL { directory.appendingPathComponent("projects.backup.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var savedAt: Date
        var projects: [Project]
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func load() throws -> LoadResult {
        if let projects = try? decode(from: liveURL) {
            return LoadResult(projects: projects, recoveredFromBackup: false)
        }
        // Live file missing entirely on first launch is not an error.
        if !FileManager.default.fileExists(atPath: liveURL.path),
           !FileManager.default.fileExists(atPath: backupURL.path) {
            return LoadResult(projects: [], recoveredFromBackup: false)
        }
        do {
            let projects = try decode(from: backupURL)
            return LoadResult(projects: projects, recoveredFromBackup: true)
        } catch {
            throw StoreError.corruptedAndNoBackup(underlying: String(describing: error))
        }
    }

    private func decode(from url: URL) throws -> [Project] {
        let data = try Data(contentsOf: url)
        return try Self.decoder().decode(Envelope.self, from: data).projects
    }

    public func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            savedAt: Date(),
            projects: projects
        )
        let data = try Self.encoder().encode(envelope)

        // Preserve the current good file before replacing it.
        if FileManager.default.fileExists(atPath: liveURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: liveURL, to: backupURL)
        }

        let tempURL = directory.appendingPathComponent("projects.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
            throw StoreError.notWritable(path: tempURL.path)
        }

        let handle = try FileHandle(forWritingTo: tempURL)
        do {
            try handle.write(contentsOf: data)
            // Force to disk before the rename, so the rename cannot expose an empty file.
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        // POSIX rename(2): atomic, and it replaces an existing destination. Readers see
        // either the complete old file or the complete new one, never a torn write.
        // Used in preference to FileManager.replaceItemAt, which needs the destination to
        // already exist and is unreliable on swift-corelibs-foundation.
        guard rename(tempURL.path, liveURL.path) == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw StoreError.notWritable(path: liveURL.path)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryProjectStore: ProjectStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var projects: [Project]
    public private(set) var saveCount = 0

    public init(projects: [Project] = []) {
        self.projects = projects
    }

    public func load() throws -> LoadResult {
        lock.lock(); defer { lock.unlock() }
        return LoadResult(projects: projects, recoveredFromBackup: false)
    }

    public func save(_ projects: [Project]) throws {
        lock.lock(); defer { lock.unlock() }
        self.projects = projects
        saveCount += 1
    }
}
