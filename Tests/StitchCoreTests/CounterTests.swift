import Testing
import Foundation
@testable import StitchCore

@Suite("Counter cascade")
struct CounterCascadeTests {

    /// "Rows 1–12, repeat 6 times" — the canonical knitting setup.
    private func repeatProject() -> (Project, UUID, UUID) {
        let repeatID = UUID()
        let rowID = UUID()
        let repeats = Counter(id: repeatID, name: "Repeat", target: 6)
        let rows = Counter(
            id: rowID, name: "Row",
            cycleLength: 12, wrapBehavior: .reset, linkedCounterID: repeatID
        )
        return (Project(name: "Sleeve", counters: [rows, repeats]), rowID, repeatID)
    }

    @Test("counting to the end of a cycle does not advance the repeat")
    func withinCycle() {
        var (p, row, rep) = repeatProject()
        for _ in 1..<12 { p.apply(.increment(row)) }
        #expect(p.counter(row)?.value == 12)
        #expect(p.counter(rep)?.value == 1)
    }

    @Test("completing a cycle resets the row and advances the repeat")
    func wrapResets() {
        var (p, row, rep) = repeatProject()
        for _ in 0..<12 { p.apply(.increment(row)) }
        #expect(p.counter(row)?.value == 1)
        #expect(p.counter(rep)?.value == 2)
    }

    @Test("six full repeats land exactly on target")
    func fullGarment() {
        var (p, row, rep) = repeatProject()
        for _ in 0..<(12 * 6) { p.apply(.increment(row)) }
        #expect(p.counter(rep)?.value == 7)   // started at 1, six cycles completed
        #expect(p.counter(row)?.value == 1)
    }

    @Test("continuous mode keeps a global row count while still advancing the repeat")
    func continuousMode() {
        let repeatID = UUID(), rowID = UUID()
        var p = Project(name: "Shawl", counters: [
            Counter(id: rowID, name: "Row", cycleLength: 4,
                    wrapBehavior: .continuous, linkedCounterID: repeatID),
            Counter(id: repeatID, name: "Repeat"),
        ])
        for _ in 0..<8 { p.apply(.increment(rowID)) }
        #expect(p.counter(rowID)?.value == 9)    // never resets
        #expect(p.counter(repeatID)?.value == 3) // two cycles completed
    }

    @Test("decrement steps back across a cycle boundary")
    func decrementAcrossBoundary() {
        var (p, row, rep) = repeatProject()
        for _ in 0..<12 { p.apply(.increment(row)) }
        #expect(p.counter(row)?.value == 1)
        #expect(p.counter(rep)?.value == 2)

        p.apply(.decrement(row))
        #expect(p.counter(row)?.value == 12)
        #expect(p.counter(rep)?.value == 1)
    }

    @Test("decrement will not go below the start value")
    func decrementFloor() {
        var (p, row, rep) = repeatProject()
        p.apply(.decrement(row))
        #expect(p.counter(row)?.value == 1)
        #expect(p.counter(rep)?.value == 1)
    }

    @Test("three-level cascade advances section on the twelfth repeat")
    func threeLevelCascade() {
        let sectionID = UUID(), repeatID = UUID(), rowID = UUID()
        var p = Project(name: "Blanket", counters: [
            Counter(id: rowID, name: "Row", cycleLength: 4, linkedCounterID: repeatID),
            Counter(id: repeatID, name: "Repeat", cycleLength: 3, linkedCounterID: sectionID),
            Counter(id: sectionID, name: "Section"),
        ])
        for _ in 0..<12 { p.apply(.increment(rowID)) }   // 4 rows x 3 repeats
        #expect(p.counter(rowID)?.value == 1)
        #expect(p.counter(repeatID)?.value == 1)
        #expect(p.counter(sectionID)?.value == 2)
    }

    @Test("a counter wired into a loop terminates instead of hanging")
    func cascadeLoopGuard() {
        let a = UUID(), b = UUID()
        var p = Project(name: "Bad", counters: [
            Counter(id: a, name: "A", cycleLength: 1, linkedCounterID: b),
            Counter(id: b, name: "B", cycleLength: 1, linkedCounterID: a),
        ])
        p.apply(.increment(a))     // must return rather than recurse forever
        #expect(p.counters.count == 2)
    }

    @Test("progress reflects the target")
    func progress() {
        var c = Counter(name: "Row", target: 101)
        c.value = 51
        #expect(c.progress == 0.5)
    }

    @Test("position within cycle is 1-based in both wrap modes")
    func positionInCycle() {
        var reset = Counter(name: "R", cycleLength: 4, wrapBehavior: .reset)
        reset.value = 4
        #expect(reset.positionInCycle == 4)

        var cont = Counter(name: "C", cycleLength: 4, wrapBehavior: .continuous)
        cont.value = 9      // start 1 -> offset 8 -> position 1
        #expect(cont.positionInCycle == 1)
    }
}

@Suite("Undo")
struct UndoTests {

    @Test("undo restores every counter a cascade touched")
    func undoRestoresCascade() {
        let repeatID = UUID(), rowID = UUID()
        var p = Project(name: "Hat", counters: [
            Counter(id: rowID, name: "Row", cycleLength: 12, linkedCounterID: repeatID),
            Counter(id: repeatID, name: "Repeat"),
        ])
        for _ in 0..<12 { p.apply(.increment(rowID)) }
        #expect(p.counter(rowID)?.value == 1)
        #expect(p.counter(repeatID)?.value == 2)

        p.undo()
        #expect(p.counter(rowID)?.value == 12)
        #expect(p.counter(repeatID)?.value == 1)
    }

    @Test("undo unwinds a long run of mis-taps exactly")
    func undoManyTimes() {
        let rowID = UUID()
        var p = Project(name: "Scarf", counters: [Counter(id: rowID, name: "Row")])
        for _ in 0..<40 { p.apply(.increment(rowID)) }
        #expect(p.counter(rowID)?.value == 41)
        for _ in 0..<15 { p.undo() }
        #expect(p.counter(rowID)?.value == 26)
    }

    @Test("undo of resetAll restores all previous values")
    func undoResetAll() {
        let a = UUID(), b = UUID()
        var p = Project(name: "Socks", counters: [
            Counter(id: a, name: "A"), Counter(id: b, name: "B"),
        ])
        for _ in 0..<5 { p.apply(.increment(a)) }
        for _ in 0..<3 { p.apply(.increment(b)) }
        p.apply(.resetAll)
        #expect(p.counter(a)?.value == 1)
        #expect(p.counter(b)?.value == 1)

        p.undo()
        #expect(p.counter(a)?.value == 6)
        #expect(p.counter(b)?.value == 4)
    }

    @Test("undo with no history is a safe no-op")
    func undoEmpty() {
        var p = Project(name: "New", counters: [Counter(name: "Row")])
        #expect(p.undo() == nil)
        #expect(p.canUndo == false)
    }

    @Test("history is bounded but still deep enough to be useful")
    func historyBounded() {
        let rowID = UUID()
        var p = Project(name: "Long", counters: [Counter(id: rowID, name: "Row")])
        for _ in 0..<(Project.historyLimit + 100) { p.apply(.increment(rowID)) }
        #expect(p.history.count == Project.historyLimit)
        #expect(Project.historyLimit >= 200)
    }

    @Test("an action that changes nothing records no history")
    func noOpNotRecorded() {
        let rowID = UUID()
        var p = Project(name: "P", counters: [Counter(id: rowID, name: "Row")])
        #expect(p.apply(.decrement(rowID)) == nil)   // already at floor
        #expect(p.history.isEmpty)
    }

    @Test("actions against an unknown counter are ignored")
    func unknownCounter() {
        var p = Project(name: "P", counters: [Counter(name: "Row")])
        #expect(p.apply(.increment(UUID())) == nil)
        #expect(p.history.isEmpty)
    }
}
