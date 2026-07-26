import Foundation
import Observation
import StitchCore

/// Single source of truth for the app.
///
/// Saves happen synchronously on every mutation. The projects file is a few kilobytes, so
/// the cost is negligible next to the guarantee it buys: there is no window in which a
/// counted row exists only in memory. This is the whole reason the app exists.
@Observable
@MainActor
final class AppState {
    private(set) var projects: [Project] = []
    private(set) var entitlements = Entitlements()
    /// Set when a load fell back to the backup file, so the UI can tell the user.
    private(set) var didRecoverFromBackup = false
    private(set) var lastError: String?

    private let store: any ProjectStoring

    init(store: any ProjectStoring) {
        self.store = store
        load()
    }

    static func makeDefault() -> AppState {
        let dir = URL.documentsDirectory.appendingPathComponent("Stitchwise", isDirectory: true)
        // UI tests need a known starting point. Guarded by a launch argument so it can
        // never fire for a real user.
        if ProcessInfo.processInfo.arguments.contains("-reset-state") {
            try? FileManager.default.removeItem(at: dir)
        }
        return AppState(store: FileProjectStore(directory: dir))
    }

    // MARK: - Persistence

    func load() {
        do {
            let result = try store.load()
            projects = result.projects
            didRecoverFromBackup = result.recoveredFromBackup
        } catch {
            // Never silently start empty over existing data — surface it instead.
            lastError = "Could not open your projects: \(error)"
        }
    }

    private func persist() {
        do {
            try store.save(projects)
            lastError = nil
        } catch {
            lastError = "Could not save: \(error)"
        }
    }

    // MARK: - Projects

    var canCreateProject: Bool {
        entitlements.canCreateProject(existingCount: projects.count)
    }

    @discardableResult
    func addProject(name: String, craft: Craft) -> Project? {
        guard canCreateProject else { return nil }
        let rowID = UUID()
        let project = Project(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            craft: craft,
            counters: [Counter(id: rowID, name: "Row")]
        )
        projects.append(project)
        persist()
        return project
    }

    func delete(_ projectID: UUID) {
        projects.removeAll { $0.id == projectID }
        persist()
    }

    func update(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        persist()
    }

    // MARK: - Counting

    func apply(_ action: CounterAction, to projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard projects[idx].apply(action) != nil else { return }
        if case .increment = action { projects[idx].recordRow() }
        persist()
    }

    func undo(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard projects[idx].undo() != nil else { return }
        persist()
    }

    func addCounter(named name: String, to projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].counters.append(Counter(name: name))
        persist()
    }

    // MARK: - Sessions

    func startSession(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].startSession()
        persist()
    }

    func stopSession(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].stopSession()
        persist()
    }

    // MARK: - Entitlement

    func setEntitlement(_ entitlement: Entitlement) {
        entitlements = Entitlements(entitlement: entitlement)
    }
}
