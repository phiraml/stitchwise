import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import StitchCore
#if canImport(UIKit)
import UIKit
#endif

/// The screen a knitter actually looks at, usually one-handed, often without looking.
///
/// Design constraints that drive the layout:
/// - the increment target fills most of the screen, so it can be hit without looking
/// - undo is permanently visible, because a mis-tap is the single most common event
/// - decrement is deliberately smaller than increment to reduce accidental hits
/// - the screen never sleeps while counting
struct CounterView: View {
    let projectID: UUID

    @Environment(AppState.self) private var state
    @State private var showingPattern = false
    @State private var showingAddCounter = false
    @State private var showingImporter = false
    @State private var newCounterName = ""

    private var project: Project? {
        state.projects.first { $0.id == projectID }
    }

    var body: some View {
        Group {
            if let project {
                content(for: project)
            } else {
                ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(project?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add counter", systemImage: "plus.circle") {
                        newCounterName = ""
                        showingAddCounter = true
                    }
                    if project?.pattern != nil {
                        Button("Open pattern", systemImage: "doc.richtext") {
                            showingPattern = true
                        }
                        Button("Remove pattern", systemImage: "doc.badge.ellipsis", role: .destructive) {
                            state.removePattern(from: projectID)
                        }
                    } else {
                        Button("Import pattern PDF", systemImage: "square.and.arrow.down") {
                            showingImporter = true
                        }
                    }
                    Button("Reset all counters", systemImage: "arrow.counterclockwise", role: .destructive) {
                        state.apply(.resetAll, to: projectID)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("projectMenuButton")
            }
        }
        .sheet(isPresented: $showingAddCounter) { addCounterSheet }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingPattern) {
            if let project, project.pattern != nil {
                PatternView(projectID: project.id)
            }
        }
        #if canImport(UIKit)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        VStack(spacing: 0) {
            secondaryCounters(project)

            if let primary = project.counters.first {
                primaryCounter(primary)
            }

            controls(project)
        }
    }

    // MARK: - Primary counter

    @ViewBuilder
    private func primaryCounter(_ counter: Counter) -> some View {
        // The tap target is a separate transparent button *behind* the readout rather than
        // wrapping it. A SwiftUI Button merges its children into a single accessibility
        // element, which would make the counter value unqueryable from UI tests.
        ZStack {
            Button(action: increment) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("incrementButton")
            .accessibilityLabel("Add a row to \(counter.name)")

            VStack(spacing: 8) {
                Text(counter.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text("\(counter.value)")
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("primaryCounterValue")

                if let position = counter.positionInCycle, let cycle = counter.cycleLength {
                    Text("Row \(position) of \(cycle) in repeat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let progress = counter.progress, let target = counter.target {
                    ProgressView(value: progress) {
                        Text("\(counter.value) of \(target)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 48)
                }
            }
            .allowsHitTesting(false)   // taps fall through to the button beneath
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Secondary counters

    @ViewBuilder
    private func secondaryCounters(_ project: Project) -> some View {
        if project.counters.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(project.counters.dropFirst()) { counter in
                        VStack(spacing: 2) {
                            Text(counter.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(counter.value)")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(minWidth: 64)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("counterChip-\(counter.name)")
                        .onTapGesture { state.apply(.increment(counter.id), to: projectID) }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ project: Project) -> some View {
        HStack(spacing: 16) {
            Button {
                if let id = project.counters.first?.id {
                    state.apply(.decrement(id), to: projectID)
                    haptic(.light)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("decrementButton")
            .accessibilityLabel("Remove a row")

            Button {
                state.undo(projectID)
                haptic(.light)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.bordered)
            .disabled(!project.canUndo)
            .accessibilityIdentifier("undoButton")

            SessionButton(project: project, projectID: projectID)
        }
        .padding()
    }

    /// Files hands back a security-scoped URL that stops working shortly after. Read the
    /// page count and hand it to the importer while access is still held; the importer
    /// copies the file into app storage so nothing depends on this URL afterwards.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let pageCount = PDFDocument(url: url)?.pageCount ?? 1
        state.importPattern(
            from: url,
            displayName: url.deletingPathExtension().lastPathComponent,
            pageCount: pageCount,
            into: projectID
        )
    }

    private func increment() {
        guard let id = project?.counters.first?.id else { return }
        state.apply(.increment(id), to: projectID)
        haptic(.medium)
    }

    private var addCounterSheet: some View {
        NavigationStack {
            Form {
                TextField("Counter name", text: $newCounterName)
                    .accessibilityIdentifier("counterNameField")
            }
            .navigationTitle("Add counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddCounter = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        state.addCounter(
                            named: newCounterName.isEmpty ? "Counter" : newCounterName,
                            to: projectID
                        )
                        showingAddCounter = false
                    }
                    .accessibilityIdentifier("confirmAddCounterButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    #if canImport(UIKit)
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    #else
    private func haptic(_ style: Int) {}
    #endif
}

private struct SessionButton: View {
    let project: Project
    let projectID: UUID
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            if project.runningSession != nil {
                state.stopSession(projectID)
            } else {
                state.startSession(projectID)
            }
        } label: {
            Image(systemName: project.runningSession != nil ? "pause.fill" : "play.fill")
                .font(.title2.weight(.semibold))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("sessionToggleButton")
        .accessibilityLabel(project.runningSession != nil ? "Pause timer" : "Start timer")
    }
}
