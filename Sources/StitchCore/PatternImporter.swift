import Foundation

/// Copies a pattern PDF into the app's own storage on import.
///
/// This is deliberately a copy, not a reference. A file picked from Files, iCloud Drive or
/// Dropbox is reachable through a security-scoped URL that expires, and the provider can
/// move or evict the original at any time — which is precisely how a pattern "disappears".
/// Once imported, the PDF is inside the app container and offline forever.
public struct PatternImporter: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public enum ImportError: Error, Equatable {
        case sourceUnreadable(String)
        case copyFailed(String)
    }

    /// Copies `sourceURL` into storage under a collision-proof name and returns the
    /// reference to persist on the project.
    ///
    /// `pageCount` is supplied by the caller because counting pages needs PDFKit, which
    /// does not exist off Apple platforms; keeping it out lets this type be tested anywhere.
    public func `import`(
        from sourceURL: URL,
        displayName: String,
        pageCount: Int,
        now: Date = Date()
    ) throws -> PatternRef {
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw ImportError.sourceUnreadable(sourceURL.path)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // UUID name rather than the original: two patterns called "shawl.pdf" must not
        // overwrite one another, and user-supplied names can contain path separators.
        let filename = "\(UUID().uuidString).pdf"
        let destination = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ImportError.copyFailed(String(describing: error))
        }

        let cleanedName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? sourceURL.deletingPathExtension().lastPathComponent
                     : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        return PatternRef(
            filename: filename,
            displayName: cleanedName,
            pageCount: max(1, pageCount),
            importedAt: now
        )
    }

    public func url(for pattern: PatternRef) -> URL {
        directory.appendingPathComponent(pattern.filename)
    }

    public func exists(_ pattern: PatternRef) -> Bool {
        FileManager.default.fileExists(atPath: url(for: pattern).path)
    }

    /// Removes the stored PDF. Safe to call when the file is already gone.
    public func delete(_ pattern: PatternRef) {
        try? FileManager.default.removeItem(at: url(for: pattern))
    }
}
