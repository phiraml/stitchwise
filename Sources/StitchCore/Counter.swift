import Foundation

public enum Craft: String, Codable, Sendable, CaseIterable {
    case knitting
    case crochet
}

/// What happens to a counter when it completes one cycle of its pattern repeat.
public enum WrapBehavior: String, Codable, Sendable {
    /// Counter returns to `start` and the linked counter advances.
    /// This is what most knitters expect for "rows 1–12, repeat 6 times".
    case reset
    /// Counter keeps climbing (global row count) while the linked counter still advances.
    case continuous
}

/// A single counter. Counters compose: a row counter with `cycleLength: 12` linked to a
/// repeat counter advances the repeat every twelfth row.
public struct Counter: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var value: Int
    /// The value a counter holds before any work is done. Knitters usually count from 1.
    public var start: Int
    public var step: Int
    /// Optional goal, e.g. 120 rows. Drives `progress`.
    public var target: Int?
    /// Increments that make one cycle, e.g. 12 rows per pattern repeat.
    /// Cycle logic applies only when `step == 1`, which is the real-world case.
    public var cycleLength: Int?
    public var wrapBehavior: WrapBehavior
    /// Counter advanced when this one completes a cycle.
    public var linkedCounterID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        value: Int? = nil,
        start: Int = 1,
        step: Int = 1,
        target: Int? = nil,
        cycleLength: Int? = nil,
        wrapBehavior: WrapBehavior = .reset,
        linkedCounterID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.start = start
        self.value = value ?? start
        self.step = step
        self.target = target
        self.cycleLength = cycleLength
        self.wrapBehavior = wrapBehavior
        self.linkedCounterID = linkedCounterID
    }

    /// 0...1 completion against `target`, or nil when no target is set.
    public var progress: Double? {
        guard let target, target > start else { return nil }
        return min(1, max(0, Double(value - start) / Double(target - start)))
    }

    /// 1-based position within the current cycle, or nil when no cycle is configured.
    /// Works for both wrap behaviours.
    public var positionInCycle: Int? {
        guard let cycleLength, cycleLength > 0 else { return nil }
        let offset = value - start
        return ((offset % cycleLength) + cycleLength) % cycleLength + 1
    }

    /// True when the next increment completes this cycle.
    var isAtCycleEnd: Bool {
        guard let cycleLength, cycleLength > 0 else { return false }
        let offset = value - start
        return ((offset % cycleLength) + cycleLength) % cycleLength == cycleLength - 1
    }

    /// True when the counter sits on the first stitch of a cycle.
    var isAtCycleStart: Bool {
        guard let cycleLength, cycleLength > 0 else { return false }
        let offset = value - start
        return ((offset % cycleLength) + cycleLength) % cycleLength == 0
    }
}
