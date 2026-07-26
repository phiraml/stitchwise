import Testing
import Foundation
@testable import StitchCore

@Suite("Pattern annotation")
struct PatternTests {

    @Test("the row highlighter is moved, not duplicated")
    func highlighterIsSingleton() {
        var p = PatternRef(filename: "a.pdf", displayName: "A", pageCount: 3)
        p.moveRowHighlighter(onPage: 0, toY: 0.1)
        p.moveRowHighlighter(onPage: 0, toY: 0.5)
        p.moveRowHighlighter(onPage: 0, toY: 0.9)

        let bars = p.annotations(onPage: 0).filter { $0.kind == .rowHighlighter }
        #expect(bars.count == 1)
        #expect(bars[0].rect.y == 0.9)
    }

    @Test("each page keeps its own highlighter")
    func highlighterPerPage() {
        var p = PatternRef(filename: "a.pdf", displayName: "A", pageCount: 3)
        p.moveRowHighlighter(onPage: 0, toY: 0.2)
        p.moveRowHighlighter(onPage: 1, toY: 0.6)
        #expect(p.annotations.filter { $0.kind == .rowHighlighter }.count == 2)
        #expect(p.annotations(onPage: 1).first?.rect.y == 0.6)
    }

    @Test("a highlighter near the page bottom is clamped inside the page")
    func clampsToPage() {
        var p = PatternRef(filename: "a.pdf", displayName: "A", pageCount: 1)
        let a = p.moveRowHighlighter(onPage: 0, toY: 0.99, height: 0.2)
        #expect(a.rect.isValid)
        #expect(a.rect.y + a.rect.height <= 1.0001)
    }

    @Test("normalised rects reject impossible geometry")
    func rectValidation() {
        #expect(NormalisedRect(x: 0, y: 0, width: 1, height: 0.05).isValid)
        #expect(!NormalisedRect(x: 0.9, y: 0, width: 0.5, height: 0.1).isValid)
        #expect(!NormalisedRect(x: 0, y: 0, width: 0, height: 0.1).isValid)
    }

    @Test("annotations are updated in place by id")
    func upsertReplaces() {
        var p = PatternRef(filename: "a.pdf", displayName: "A", pageCount: 1)
        var note = Annotation(
            pageIndex: 0, kind: .note,
            rect: NormalisedRect(x: 0, y: 0, width: 0.2, height: 0.1),
            text: "first"
        )
        p.upsert(note)
        note.text = "second"
        p.upsert(note)

        #expect(p.annotations.count == 1)
        #expect(p.annotations[0].text == "second")

        p.remove(note.id)
        #expect(p.annotations.isEmpty)
    }
}

@Suite("Calculators")
struct CalculatorTests {

    @Test("cast-on from gauge")
    func castOn() {
        let g = Gauge(stitches: 22, rows: 30, over: 10)
        #expect(g.castOn(forWidthCm: 50) == 110)
        #expect(g.rows(forLengthCm: 60) == 180)
    }

    @Test("a tighter knitter needs more stitches for the same width")
    func gaugeAdjustment() {
        let pattern = Gauge(stitches: 20, rows: 28)
        let mine = Gauge(stitches: 24, rows: 32)   // tighter
        let adjusted = GaugeAdjustment.adjustedStitchCount(
            patternStitches: 100, patternGauge: pattern, myGauge: mine
        )
        #expect(adjusted == 120)
    }

    @Test("a looser knitter needs fewer stitches")
    func gaugeAdjustmentLooser() {
        let pattern = Gauge(stitches: 24, rows: 32)
        let mine = Gauge(stitches: 20, rows: 28)
        let adjusted = GaugeAdjustment.adjustedStitchCount(
            patternStitches: 120, patternGauge: pattern, myGauge: mine
        )
        #expect(adjusted == 100)
    }

    @Test("row counts adjust independently of stitch counts")
    func rowAdjustment() {
        let pattern = Gauge(stitches: 20, rows: 28)
        let mine = Gauge(stitches: 20, rows: 35)
        let adjusted = GaugeAdjustment.adjustedRowCount(
            patternRows: 56, patternGauge: pattern, myGauge: mine
        )
        #expect(adjusted == 70)
    }

    @Test("identical gauge changes nothing")
    func identicalGauge() {
        let g = Gauge(stitches: 22, rows: 30)
        #expect(GaugeAdjustment.adjustedStitchCount(patternStitches: 88, patternGauge: g, myGauge: g) == 88)
    }

    @Test("zero gauge is handled instead of dividing by zero")
    func zeroGauge() {
        let zero = Gauge(stitches: 0, rows: 0)
        let real = Gauge(stitches: 20, rows: 28)
        #expect(GaugeAdjustment.adjustedStitchCount(patternStitches: 100, patternGauge: zero, myGauge: real) == 0)
        #expect(zero.castOn(forWidthCm: 50) == 0)
    }

    @Test("stitch counts round to whole pattern repeats plus edges")
    func roundToRepeat() {
        #expect(GaugeAdjustment.roundToRepeat(stitches: 100, repeatWidth: 12, edgeStitches: 4) == 100)
        #expect(GaugeAdjustment.roundToRepeat(stitches: 103, repeatWidth: 12, edgeStitches: 4) == 100)
        #expect(GaugeAdjustment.roundToRepeat(stitches: 107, repeatWidth: 12, edgeStitches: 4) == 112)
    }

    @Test("even shaping interval")
    func shaping() {
        let r = ShapingCalculator.interval(changes: 12, overRows: 48)
        #expect(r?.every == 4)
        #expect(r?.times == 12)
        #expect(ShapingCalculator.interval(changes: 0, overRows: 10) == nil)
        #expect(ShapingCalculator.interval(changes: 20, overRows: 10) == nil)
    }
}

@Suite("Time tracking")
struct TimeTrackingTests {

    @Test("starting twice does not create overlapping sessions")
    func startIsIdempotent() {
        var p = Project(name: "P")
        let t0 = Date(timeIntervalSinceReferenceDate: 0)   // fixed base keeps timings exact
        p.startSession(at: t0)
        p.startSession(at: t0.addingTimeInterval(5))
        #expect(p.sessions.count == 1)
    }

    @Test("total time accumulates across sessions")
    func totalTime() {
        var p = Project(name: "P")
        let t0 = Date(timeIntervalSinceReferenceDate: 0)   // fixed base keeps timings exact
        p.startSession(at: t0)
        p.stopSession(at: t0.addingTimeInterval(600))
        p.startSession(at: t0.addingTimeInterval(1000))
        p.stopSession(at: t0.addingTimeInterval(1300))
        #expect(p.totalTime(now: t0.addingTimeInterval(2000)) == 900)
    }

    @Test("a running session counts toward the total")
    func runningCounts() {
        var p = Project(name: "P")
        let t0 = Date(timeIntervalSinceReferenceDate: 0)   // fixed base keeps timings exact
        p.startSession(at: t0)
        #expect(p.totalTime(now: t0.addingTimeInterval(120)) == 120)
    }

    @Test("pace and remaining-time estimate")
    func estimate() {
        let rowID = UUID()
        var p = Project(name: "P", counters: [Counter(id: rowID, name: "Row", target: 101)])
        let t0 = Date(timeIntervalSinceReferenceDate: 0)   // fixed base keeps timings exact
        p.startSession(at: t0)
        p.recordRow(count: 10)
        p.stopSession(at: t0.addingTimeInterval(600))   // 60s per row

        #expect(p.averageSecondsPerRow(now: t0.addingTimeInterval(600)) == 60)

        p.apply(.setValue(rowID, 51))
        let remaining = p.estimatedTimeRemaining(for: rowID, now: t0.addingTimeInterval(600))
        #expect(remaining == 3000.0)   // 50 rows remaining at 60s each
    }

    @Test("no pace data yields no estimate rather than a wrong one")
    func noEstimateWithoutData() {
        let rowID = UUID()
        let p = Project(name: "P", counters: [Counter(id: rowID, name: "Row", target: 100)])
        #expect(p.averageSecondsPerRow() == nil)
        #expect(p.estimatedTimeRemaining(for: rowID) == nil)
    }

    @Test("stopping without a running session is a safe no-op")
    func stopWithoutStart() {
        var p = Project(name: "P")
        #expect(p.stopSession() == nil)
    }
}
