import Foundation

/// A stretch of knitting time. `endedAt == nil` means the session is still running.
public struct TimeSession: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// Rows completed during the session, captured so the app can show rows-per-hour
    /// without re-deriving it from counter history.
    public var rowsCompleted: Int

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, rowsCompleted: Int = 0) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rowsCompleted = rowsCompleted
    }

    public var isRunning: Bool { endedAt == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

extension Project {
    public var runningSession: TimeSession? {
        sessions.first { $0.isRunning }
    }

    /// Starts a session. Idempotent: if one is already running it is returned unchanged,
    /// so a double-tap or a relaunch cannot create overlapping sessions.
    @discardableResult
    public mutating func startSession(at date: Date = Date()) -> TimeSession {
        if let running = runningSession { return running }
        let session = TimeSession(startedAt: date)
        sessions.append(session)
        updatedAt = date
        return session
    }

    @discardableResult
    public mutating func stopSession(at date: Date = Date()) -> TimeSession? {
        guard let idx = sessions.firstIndex(where: { $0.isRunning }) else { return nil }
        sessions[idx].endedAt = max(date, sessions[idx].startedAt)
        updatedAt = date
        return sessions[idx]
    }

    /// Total tracked time, including a session still in progress.
    public func totalTime(now: Date = Date()) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(now: now) }
    }

    public func totalRows() -> Int {
        sessions.reduce(0) { $0 + $1.rowsCompleted }
    }

    /// Average seconds per row across completed work, or nil when there is nothing to average.
    public func averageSecondsPerRow(now: Date = Date()) -> Double? {
        let rows = totalRows()
        guard rows > 0 else { return nil }
        let time = totalTime(now: now)
        guard time > 0 else { return nil }
        return time / Double(rows)
    }

    /// Projected time remaining for a counter with a target, based on observed pace.
    public func estimatedTimeRemaining(for counterID: UUID, now: Date = Date()) -> TimeInterval? {
        guard let counter = counter(counterID),
              let target = counter.target,
              let pace = averageSecondsPerRow(now: now) else { return nil }
        let remaining = target - counter.value
        guard remaining > 0 else { return 0 }
        return Double(remaining) * pace
    }

    /// Records rows against the running session. Called when a counter the user has marked
    /// as the row counter advances.
    public mutating func recordRow(count: Int = 1) {
        guard let idx = sessions.firstIndex(where: { $0.isRunning }) else { return }
        sessions[idx].rowsCompleted = max(0, sessions[idx].rowsCompleted + count)
    }
}
