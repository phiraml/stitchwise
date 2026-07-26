import Foundation

/// Gauge measured over a swatch. Stored per 10 cm, the standard on pattern labels.
public struct Gauge: Codable, Sendable, Equatable {
    public var stitches: Double
    public var rows: Double
    /// Swatch measurement span in centimetres. Patterns quote 10 cm; some quote 4 inches.
    public var over: Double

    public init(stitches: Double, rows: Double, over: Double = 10) {
        self.stitches = stitches
        self.rows = rows
        self.over = over
    }

    public var stitchesPerCm: Double { over > 0 ? stitches / over : 0 }
    public var rowsPerCm: Double { over > 0 ? rows / over : 0 }

    /// Cast-on count for a finished width. Rounds to nearest whole stitch.
    public func castOn(forWidthCm width: Double) -> Int {
        guard stitchesPerCm > 0, width > 0 else { return 0 }
        return Int((width * stitchesPerCm).rounded())
    }

    /// Rows needed for a finished length.
    public func rows(forLengthCm length: Double) -> Int {
        guard rowsPerCm > 0, length > 0 else { return 0 }
        return Int((length * rowsPerCm).rounded())
    }

    public func widthCm(forStitches count: Int) -> Double {
        guard stitchesPerCm > 0 else { return 0 }
        return Double(count) / stitchesPerCm
    }

    public func lengthCm(forRows count: Int) -> Double {
        guard rowsPerCm > 0 else { return 0 }
        return Double(count) / rowsPerCm
    }
}

public enum GaugeAdjustment {
    /// Recomputes a pattern's stitch count for a knitter whose gauge differs.
    ///
    /// This is the calculation people get wrong by hand and the reason a finished garment
    /// comes out the wrong size: the pattern's stitch count only holds at the pattern's gauge.
    public static func adjustedStitchCount(
        patternStitches: Int,
        patternGauge: Gauge,
        myGauge: Gauge
    ) -> Int {
        guard patternGauge.stitchesPerCm > 0, myGauge.stitchesPerCm > 0, patternStitches > 0 else {
            return 0
        }
        let targetWidth = patternGauge.widthCm(forStitches: patternStitches)
        return myGauge.castOn(forWidthCm: targetWidth)
    }

    /// Same correction for row counts.
    public static func adjustedRowCount(
        patternRows: Int,
        patternGauge: Gauge,
        myGauge: Gauge
    ) -> Int {
        guard patternGauge.rowsPerCm > 0, myGauge.rowsPerCm > 0, patternRows > 0 else {
            return 0
        }
        let targetLength = patternGauge.lengthCm(forRows: patternRows)
        return myGauge.rows(forLengthCm: targetLength)
    }

    /// Rounds a stitch count up to the next whole pattern repeat, keeping any edge stitches.
    /// Returns the original count when it already fits.
    public static func roundToRepeat(
        stitches: Int,
        repeatWidth: Int,
        edgeStitches: Int = 0
    ) -> Int {
        guard repeatWidth > 0, stitches > edgeStitches else { return stitches }
        let body = stitches - edgeStitches
        let repeats = Int((Double(body) / Double(repeatWidth)).rounded())
        return max(repeatWidth, repeats * repeatWidth) + edgeStitches
    }
}

public enum ShapingCalculator {
    /// Even shaping: distribute `changes` increases or decreases across `rows`.
    /// Returns the row interval and how many changes land on it.
    ///
    /// Patterns say "decrease every 4th row 12 times"; knitters working from measurements
    /// have to derive that, and getting it wrong puts the shaping in the wrong place.
    public static func interval(changes: Int, overRows rows: Int) -> (every: Int, times: Int)? {
        guard changes > 0, rows > 0, changes <= rows else { return nil }
        let every = max(1, rows / changes)
        return (every: every, times: changes)
    }
}
