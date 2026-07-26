import Testing
import Foundation
@testable import StitchCore

@Suite("Durability")
struct StoreTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stitchwise-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("saves and loads a project unchanged")
    func roundTrip() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(directory: dir)

        let rowID = UUID()
        var project = Project(name: "Cardigan", craft: .crochet, counters: [
            Counter(id: rowID, name: "Row", cycleLength: 8),
        ])
        for _ in 0..<20 { project.apply(.increment(rowID)) }
        project.yarn = YarnInfo(name: "Merino", colourway: "Moss", needleSize: "4mm", skeins: 6)

        try store.save([project])
        let result = try store.load()

        #expect(result.recoveredFromBackup == false)
        #expect(result.projects.count == 1)
        #expect(result.projects[0].name == "Cardigan")
        #expect(result.projects[0].craft == .crochet)
        #expect(result.projects[0].counter(rowID)?.value == project.counter(rowID)?.value)
        #expect(result.projects[0].yarn?.skeins == 6)
    }

    @Test("first launch with no file returns empty, not an error")
    func firstLaunch() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let result = try FileProjectStore(directory: dir).load()
        #expect(result.projects.isEmpty)
        #expect(result.recoveredFromBackup == false)
    }

    /// The LoopCraft failure mode: the live file is destroyed. A knitter must not lose work.
    @Test("a corrupted live file is recovered from backup")
    func recoversFromCorruption() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(directory: dir)

        let rowID = UUID()
        var project = Project(name: "Shawl", counters: [Counter(id: rowID, name: "Row")])
        for _ in 0..<30 { project.apply(.increment(rowID)) }
        try store.save([project])      // generation 1

        project.apply(.increment(rowID))
        try store.save([project])      // generation 2, generation 1 becomes the backup

        // Simulate the disaster: live file truncated to garbage.
        let live = dir.appendingPathComponent("projects.json")
        try Data("{ not json".utf8).write(to: live)

        let result = try store.load()
        #expect(result.recoveredFromBackup == true)
        #expect(result.projects.count == 1)
        #expect(result.projects[0].name == "Shawl")
        // Recovers the previous generation — 30 rows, not zero.
        #expect(result.projects[0].counter(rowID)?.value == 31)
    }

    @Test("an empty live file is recovered from backup")
    func recoversFromEmptyFile() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(directory: dir)
        let project = Project(name: "Socks", counters: [Counter(name: "Row")])
        try store.save([project])
        try store.save([project])

        try Data().write(to: dir.appendingPathComponent("projects.json"))

        let result = try store.load()
        #expect(result.recoveredFromBackup == true)
        #expect(result.projects[0].name == "Socks")
    }

    @Test("corruption with no backup surfaces an error rather than silent data loss")
    func corruptNoBackup() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("projects.json"))

        #expect(throws: StoreError.self) {
            _ = try FileProjectStore(directory: dir).load()
        }
    }

    @Test("saving repeatedly leaves no temp files behind")
    func noTempLeak() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(directory: dir)
        let project = Project(name: "P", counters: [Counter(name: "Row")])
        for _ in 0..<10 { try store.save([project]) }

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains("projects.json"))
        #expect(files.filter { $0.hasSuffix(".tmp") }.isEmpty)
    }

    @Test("a project with a pattern and annotations survives a round trip")
    func patternRoundTrip() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(directory: dir)

        var pattern = PatternRef(filename: "abc.pdf", displayName: "Aran Jumper", pageCount: 7)
        pattern.moveRowHighlighter(onPage: 2, toY: 0.42)
        pattern.upsert(Annotation(
            pageIndex: 3,
            kind: .note,
            rect: NormalisedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05),
            text: "size 4 — 96 sts"
        ))

        var project = Project(name: "Jumper")
        project.pattern = pattern
        project.pattern?.lastPageIndex = 3

        try store.save([project])
        let loaded = try store.load().projects[0]

        #expect(loaded.pattern?.pageCount == 7)
        #expect(loaded.pattern?.lastPageIndex == 3)
        #expect(loaded.pattern?.annotations.count == 2)
        #expect(loaded.pattern?.annotations(onPage: 3).first?.text == "size 4 — 96 sts")
    }
}
