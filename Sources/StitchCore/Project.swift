import Foundation

/// An action a knitter can take against a project's counters.
public enum CounterAction: Sendable, Equatable {
    case increment(UUID)
    case decrement(UUID)
    case setValue(UUID, Int)
    case reset(UUID)
    case resetAll
}

/// A reversible record of one action. Storing the *previous* values makes undo exact
/// rather than a re-derivation, which is what stops counts drifting after a mis-tap.
public struct Mutation: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var at: Date
    public var previous: [UUID: Int]

    public init(id: UUID = UUID(), label: String, at: Date = Date(), previous: [UUID: Int]) {
        self.id = id
        self.label = label
        self.at = at
        self.previous = previous
    }
}

public struct YarnInfo: Codable, Sendable, Equatable {
    public var name: String
    public var colourway: String
    public var needleSize: String
    public var skeins: Int?

    public init(name: String = "", colourway: String = "", needleSize: String = "", skeins: Int? = nil) {
        self.name = name
        self.colourway = colourway
        self.needleSize = needleSize
        self.skeins = skeins
    }
}

public struct Project: Identifiable, Codable, Sendable, Equatable {
    /// Kept deliberately generous — a mis-tap noticed twenty rows later is still recoverable.
    public static let historyLimit = 250
    /// Guards against a user wiring counters into a cycle.
    static let maxCascadeDepth = 8

    public var id: UUID
    public var name: String
    public var craft: Craft
    public var counters: [Counter]
    public var history: [Mutation]
    public var sessions: [TimeSession]
    public var pattern: PatternRef?
    public var yarn: YarnInfo?
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        craft: Craft = .knitting,
        counters: [Counter] = [],
        history: [Mutation] = [],
        sessions: [TimeSession] = [],
        pattern: PatternRef? = nil,
        yarn: YarnInfo? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.craft = craft
        self.counters = counters
        self.history = history
        self.sessions = sessions
        self.pattern = pattern
        self.yarn = yarn
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func counter(_ id: UUID) -> Counter? {
        counters.first { $0.id == id }
    }

    public var canUndo: Bool { !history.isEmpty }

    // MARK: - Applying actions

    @discardableResult
    public mutating func apply(_ action: CounterAction, at date: Date = Date()) -> Mutation? {
        var changed: [UUID: Int] = [:]
        let label: String

        switch action {
        case .increment(let id):
            guard counters.contains(where: { $0.id == id }) else { return nil }
            label = "Increment"
            advance(id, direction: 1, changed: &changed)

        case .decrement(let id):
            guard counters.contains(where: { $0.id == id }) else { return nil }
            label = "Decrement"
            advance(id, direction: -1, changed: &changed)

        case .setValue(let id, let newValue):
            guard let idx = counters.firstIndex(where: { $0.id == id }) else { return nil }
            label = "Set value"
            changed[id] = counters[idx].value
            counters[idx].value = max(counters[idx].start, newValue)

        case .reset(let id):
            guard let idx = counters.firstIndex(where: { $0.id == id }) else { return nil }
            label = "Reset"
            changed[id] = counters[idx].value
            counters[idx].value = counters[idx].start

        case .resetAll:
            label = "Reset all"
            for idx in counters.indices where counters[idx].value != counters[idx].start {
                changed[counters[idx].id] = counters[idx].value
                counters[idx].value = counters[idx].start
            }
        }

        // Drop counters whose value did not actually move — a decrement at the floor, say.
        // Without this, undo history fills with entries that appear to do nothing when used.
        changed = changed.filter { id, previousValue in
            guard let current = counters.first(where: { $0.id == id })?.value else { return false }
            return current != previousValue
        }
        guard !changed.isEmpty else { return nil }

        let mutation = Mutation(label: label, at: date, previous: changed)
        history.append(mutation)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
        updatedAt = date
        return mutation
    }

    /// Restores the values captured before the most recent action. Exact, not re-derived.
    @discardableResult
    public mutating func undo(at date: Date = Date()) -> Mutation? {
        guard let last = history.popLast() else { return nil }
        for (counterID, previousValue) in last.previous {
            guard let idx = counters.firstIndex(where: { $0.id == counterID }) else { continue }
            counters[idx].value = previousValue
        }
        updatedAt = date
        return last
    }

    // MARK: - Cascade

    /// Moves a counter one step, cascading into its linked counter when a cycle boundary
    /// is crossed. Records the pre-change value of every counter it touches.
    private mutating func advance(
        _ counterID: UUID,
        direction: Int,
        changed: inout [UUID: Int],
        depth: Int = 0
    ) {
        guard depth < Self.maxCascadeDepth,
              let idx = counters.firstIndex(where: { $0.id == counterID }) else { return }

        // A counter already touched in this cascade means the user built a loop; stop.
        if changed[counterID] != nil && depth > 0 { return }
        if changed[counterID] == nil { changed[counterID] = counters[idx].value }

        let cycleActive = (counters[idx].cycleLength ?? 0) > 0 && counters[idx].step == 1

        if direction > 0 {
            if cycleActive && counters[idx].isAtCycleEnd {
                switch counters[idx].wrapBehavior {
                case .reset: counters[idx].value = counters[idx].start
                case .continuous: counters[idx].value += 1
                }
                if let linked = counters[idx].linkedCounterID {
                    advance(linked, direction: 1, changed: &changed, depth: depth + 1)
                }
                return
            }
            counters[idx].value += counters[idx].step
        } else {
            if cycleActive,
               counters[idx].isAtCycleStart,
               let linkedID = counters[idx].linkedCounterID,
               let lIdx = counters.firstIndex(where: { $0.id == linkedID }),
               counters[lIdx].value > counters[lIdx].start {
                switch counters[idx].wrapBehavior {
                case .reset: counters[idx].value = counters[idx].start + (counters[idx].cycleLength ?? 1) - 1
                case .continuous: counters[idx].value -= 1
                }
                advance(linkedID, direction: -1, changed: &changed, depth: depth + 1)
                return
            }
            counters[idx].value = max(counters[idx].start, counters[idx].value - counters[idx].step)
        }
    }
}
