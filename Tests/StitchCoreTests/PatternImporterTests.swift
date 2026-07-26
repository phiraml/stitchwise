import Testing
import Foundation
@testable import StitchCore

@Suite("Pattern import")
struct PatternImporterTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitchwise-import-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSourceFile(_ dir: URL, named: String, contents: String = "%PDF-1.4 fake") -> URL {
        let url = dir.appendingPathComponent(named)
        try? Data(contents.utf8).write(to: url)
        return url
    }

    @Test("importing copies the file into app storage")
    func importsCopy() throws {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let source = makeSourceFile(work, named: "shawl.pdf")
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))

        let ref = try importer.import(from: source, displayName: "Autumn Shawl", pageCount: 9)

        #expect(ref.displayName == "Autumn Shawl")
        #expect(ref.pageCount == 9)
        #expect(importer.exists(ref))
        // The original is untouched.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    /// Two patterns with the same filename must not clobber each other.
    @Test("identically named patterns get distinct storage")
    func noCollision() throws {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))

        let a = makeSourceFile(work, named: "pattern.pdf", contents: "first")
        let refA = try importer.import(from: a, displayName: "First", pageCount: 2)

        let b = work.appendingPathComponent("second/pattern.pdf")
        try FileManager.default.createDirectory(
            at: b.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("second".utf8).write(to: b)
        let refB = try importer.import(from: b, displayName: "Second", pageCount: 3)

        #expect(refA.filename != refB.filename)
        #expect(importer.exists(refA))
        #expect(importer.exists(refB))
        #expect(try Data(contentsOf: importer.url(for: refA)) == Data("first".utf8))
        #expect(try Data(contentsOf: importer.url(for: refB)) == Data("second".utf8))
    }

    @Test("an empty display name falls back to the filename")
    func fallbackName() throws {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let source = makeSourceFile(work, named: "cabled-jumper.pdf")
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))

        let ref = try importer.import(from: source, displayName: "   ", pageCount: 1)
        #expect(ref.displayName == "cabled-jumper")
    }

    @Test("a missing source is reported rather than silently succeeding")
    func missingSource() {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))
        #expect(throws: PatternImporter.ImportError.self) {
            _ = try importer.import(
                from: work.appendingPathComponent("nope.pdf"),
                displayName: "X", pageCount: 1
            )
        }
    }

    @Test("page count is never zero")
    func pageCountFloor() throws {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let source = makeSourceFile(work, named: "a.pdf")
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))
        let ref = try importer.import(from: source, displayName: "A", pageCount: 0)
        #expect(ref.pageCount == 1)
    }

    @Test("deleting is safe and idempotent")
    func deleteIdempotent() throws {
        let work = tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let source = makeSourceFile(work, named: "a.pdf")
        let importer = PatternImporter(directory: work.appendingPathComponent("Patterns"))
        let ref = try importer.import(from: source, displayName: "A", pageCount: 1)

        importer.delete(ref)
        #expect(!importer.exists(ref))
        importer.delete(ref)   // must not throw
        #expect(!importer.exists(ref))
    }
}
