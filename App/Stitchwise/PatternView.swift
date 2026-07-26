import SwiftUI
import PDFKit
import StitchCore

/// Pattern reader with the feature knitters ask for above all others: a highlighter bar
/// locked to the row being worked, which stays put across zoom, rotation and app restarts.
///
/// Annotations are stored as fractions of the page (`NormalisedRect`), never as points, so
/// they land in the same place on any device and at any zoom level. The PDF file itself is
/// never modified — annotations live alongside it, so the original pattern is always intact.
struct PatternView: View {
    let projectID: UUID

    @Environment(AppState.self) private var state
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var document: PDFDocument?
    @State private var pageImage: UIImage?
    @State private var page = 0
    @State private var zoom: CGFloat = 1
    @State private var showingPaywall = false

    private var project: Project? { state.projects.first { $0.id == projectID } }
    private var pattern: PatternRef? { project?.pattern }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        if let pageImage {
                            Image(uiImage: pageImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width * zoom)
                                .overlay(alignment: .topLeading) {
                                    annotationLayer(in: CGSize(
                                        width: geo.size.width * zoom,
                                        height: geo.size.width * zoom * aspect
                                    ))
                                }
                                .accessibilityIdentifier("patternPageImage")
                        } else {
                            ProgressView().frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
            }
            .navigationTitle(pattern?.displayName ?? "Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: page) { await renderPage() }
            .onAppear {
                page = pattern?.lastPageIndex ?? 0
                loadDocument()
            }
            .onDisappear { persistLastPage() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var aspect: CGFloat {
        guard let img = pageImage, img.size.width > 0 else { return 1.3 }
        return img.size.height / img.size.width
    }

    // MARK: - Annotation layer

    @ViewBuilder
    private func annotationLayer(in size: CGSize) -> some View {
        if let pattern {
            ZStack(alignment: .topLeading) {
                ForEach(pattern.annotations(onPage: page)) { annotation in
                    annotationShape(annotation, in: size)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func annotationShape(_ annotation: Annotation, in size: CGSize) -> some View {
        let rect = CGRect(
            x: annotation.rect.x * size.width,
            y: annotation.rect.y * size.height,
            width: annotation.rect.width * size.width,
            height: annotation.rect.height * size.height
        )

        switch annotation.kind {
        case .rowHighlighter:
            RowHighlighterBar(
                colour: Color(hex: annotation.colourHex),
                opacity: annotation.opacity
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityIdentifier("rowHighlighter")
            .gesture(
                DragGesture()
                    .onChanged { value in
                        moveHighlighter(toY: (value.location.y) / size.height)
                    }
            )

        case .columnBand, .highlight:
            Rectangle()
                .fill(Color(hex: annotation.colourHex).opacity(annotation.opacity))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

        case .strikeThrough:
            Rectangle()
                .fill(Color(hex: annotation.colourHex))
                .frame(width: rect.width, height: max(1, rect.height * 0.1))
                .offset(x: rect.minX, y: rect.midY)
                .allowsHitTesting(false)

        case .note:
            Image(systemName: "note.text")
                .padding(6)
                .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                page = max(0, page - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page == 0)
            .accessibilityIdentifier("previousPageButton")

            Text("\(page + 1) / \(pattern?.pageCount ?? 1)")
                .font(.footnote.monospacedDigit())
                .accessibilityIdentifier("pageIndicator")

            Button {
                page = min((pattern?.pageCount ?? 1) - 1, page + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(page >= (pattern?.pageCount ?? 1) - 1)
            .accessibilityIdentifier("nextPageButton")

            Spacer()

            Button {
                guard purchases.entitlement.isLifetime else { showingPaywall = true; return }
                moveHighlighter(toY: 0.45)
            } label: {
                Image(systemName: "highlighter")
            }
            .accessibilityIdentifier("addHighlighterButton")
        }
    }

    // MARK: - Actions

    private func moveHighlighter(toY y: CGFloat) {
        guard purchases.entitlement.isLifetime else { showingPaywall = true; return }
        guard var project, var pattern = project.pattern else { return }
        pattern.moveRowHighlighter(onPage: page, toY: Double(max(0, min(1, y))))
        project.pattern = pattern
        state.update(project)
    }

    private func persistLastPage() {
        guard var project, var pattern = project.pattern, pattern.lastPageIndex != page else { return }
        pattern.lastPageIndex = page
        project.pattern = pattern
        state.update(project)
    }

    private func loadDocument() {
        guard let pattern else { return }
        let url = URL.documentsDirectory
            .appendingPathComponent("Stitchwise/Patterns", isDirectory: true)
            .appendingPathComponent(pattern.filename)
        document = PDFDocument(url: url)
    }

    private func renderPage() async {
        guard let document, let pdfPage = document.page(at: page) else { return }
        let bounds = pdfPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: bounds.width * scale, height: bounds.height * scale)
        )
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(
                width: bounds.width * scale, height: bounds.height * scale
            )))
            ctx.cgContext.translateBy(x: 0, y: bounds.height * scale)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            pdfPage.draw(with: .mediaBox, to: ctx.cgContext)
        }
        pageImage = image
    }
}

/// A bar with a bright leading edge, so the eye lands on the row without the fill
/// obscuring the stitches underneath.
private struct RowHighlighterBar: View {
    let colour: Color
    let opacity: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(colour.opacity(opacity))
            Rectangle().fill(colour).frame(width: 4)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(colour)
                .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
    }
}

extension Color {
    /// Six-digit sRGB hex, with or without a leading '#'. Falls back to yellow.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .yellow
            return
        }
        self = Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
