import SwiftUI
import StitchCore

struct ProjectListView: View {
    @Environment(AppState.self) private var state
    @Environment(PurchaseManager.self) private var purchases

    @State private var showingNew = false
    @State private var showingPaywall = false
    @State private var newName = ""
    @State private var newCraft: Craft = .knitting

    var body: some View {
        NavigationStack {
            Group {
                if state.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No projects yet", systemImage: "circle.grid.cross")
                    } description: {
                        Text("Add a project to start counting rows.")
                    } actions: {
                        Button("New project") { startNewProject() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("emptyStateNewProjectButton")
                    }
                } else {
                    List {
                        if state.didRecoverFromBackup {
                            RecoveryNotice()
                        }
                        ForEach(state.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectRow(project: project)
                            }
                            .accessibilityIdentifier("projectRow-\(project.name)")
                        }
                        .onDelete { offsets in
                            offsets.map { state.projects[$0].id }.forEach(state.delete)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { id in
                if let project = state.projects.first(where: { $0.id == id }) {
                    CounterView(projectID: project.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startNewProject()
                    } label: {
                        Label("New project", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newProjectButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !purchases.entitlement.isLifetime {
                        Button("Unlock") { showingPaywall = true }
                            .accessibilityIdentifier("unlockButton")
                    }
                }
            }
            .sheet(isPresented: $showingNew) { newProjectSheet }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("Something went wrong", isPresented: .constant(state.lastError != nil)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.lastError ?? "")
            }
        }
    }

    private func startNewProject() {
        if state.canCreateProject {
            newName = ""
            showingNew = true
        } else {
            showingPaywall = true
        }
    }

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $newName)
                    .accessibilityIdentifier("projectNameField")
                Picker("Craft", selection: $newCraft) {
                    Text("Knitting").tag(Craft.knitting)
                    Text("Crochet").tag(Craft.crochet)
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        state.addProject(
                            name: newName.isEmpty ? "Untitled" : newName,
                            craft: newCraft
                        )
                        showingNew = false
                    }
                    .accessibilityIdentifier("confirmAddProjectButton")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name).font(.headline)
            HStack(spacing: 12) {
                Label(project.craft == .knitting ? "Knitting" : "Crochet",
                      systemImage: project.craft == .knitting ? "scribble" : "circle.hexagongrid")
                if let row = project.counters.first {
                    Text("\(row.name) \(row.value)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Shown when a load fell back to the backup file. Silence here would be the same failure
/// the app exists to avoid — the user must know which generation of their work they have.
private struct RecoveryNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Restored from backup").font(.subheadline.weight(.semibold))
                Text("The main file was damaged, so your previous save was loaded. Check your row counts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "arrow.clockwise.icloud")
        }
        .accessibilityIdentifier("recoveryNotice")
    }
}

extension Entitlement {
    var isLifetime: Bool { self == .lifetime }
}
