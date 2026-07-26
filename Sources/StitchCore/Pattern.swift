import Foundation

/// Normalised rectangle in PDF page space: origin and size expressed as 0...1 fractions of
/// the page. Storing fractions rather than points keeps annotations correct across zoom,
/// rotation and device size, and keeps this type free of PDFKit so it tests anywhere.
public struct NormalisedRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isValid: Bool {
        width > 0 && height > 0 &&
        x >= 0 && y >= 0 &&
        x + width <= 1.0001 && y + height <= 1.0001
    }

    public func clamped() -> NormalisedRect {
        let cx = min(max(x, 0), 1)
        let cy = min(max(y, 0), 1)
        return NormalisedRect(
            x: cx,
            y: cy,
            width: min(max(width, 0), 1 - cx),
            height: min(max(height, 0), 1 - cy)
        )
    }
}

public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
    /// Full-width bar locked to the row being worked — the feature knitters ask for most.
    case rowHighlighter
    /// Vertical band for tracking a column in a chart.
    case columnBand
    /// Free highlight over an instruction.
    case highlight
    /// Anchored text note.
    case note
    /// Strikethrough for completed sections.
    case strikeThrough
}

public struct Annotation: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var pageIndex: Int
    public var kind: AnnotationKind
    public var rect: NormalisedRect
    /// sRGB hex without alpha, e.g. "FFD54F".
    public var colourHex: String
    public var opacity: Double
    public var text: String

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        kind: AnnotationKind,
        rect: NormalisedRect,
        colourHex: String = "FFD54F",
        opacity: Double = 0.4,
        text: String = ""
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.kind = kind
        self.rect = rect
        self.colourHex = colourHex
        self.opacity = opacity
        self.text = text
    }
}

/// Reference to an imported pattern file.
///
/// The PDF itself is copied into the app container on import and referenced by relative
/// filename. Nothing points at a cloud provider or a security-scoped URL that can evaporate:
/// once imported, the pattern is the user's, offline, permanently.
public struct PatternRef: Codable, Sendable, Equatable {
    public var filename: String
    public var displayName: String
    public var pageCount: Int
    public var annotations: [Annotation]
    public var importedAt: Date
    /// Page the knitter was last looking at, so a project reopens where they left off.
    public var lastPageIndex: Int

    public init(
        filename: String,
        displayName: String,
        pageCount: Int,
        annotations: [Annotation] = [],
        importedAt: Date = Date(),
        lastPageIndex: Int = 0
    ) {
        self.filename = filename
        self.displayName = displayName
        self.pageCount = pageCount
        self.annotations = annotations
        self.importedAt = importedAt
        self.lastPageIndex = lastPageIndex
    }

    public func annotations(onPage page: Int) -> [Annotation] {
        annotations.filter { $0.pageIndex == page }
    }

    public mutating func upsert(_ annotation: Annotation) {
        if let idx = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[idx] = annotation
        } else {
            annotations.append(annotation)
        }
    }

    public mutating func remove(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// Moves the row highlighter on a page to a new vertical position, creating it if absent.
    /// Returns the annotation so the caller can persist it.
    @discardableResult
    public mutating func moveRowHighlighter(
        onPage page: Int,
        toY y: Double,
        height: Double = 0.035,
        colourHex: String = "FFD54F"
    ) -> Annotation {
        let rect = NormalisedRect(x: 0, y: y, width: 1, height: height).clamped()
        if var existing = annotations.first(where: { $0.pageIndex == page && $0.kind == .rowHighlighter }) {
            existing.rect = rect
            upsert(existing)
            return existing
        }
        let created = Annotation(
            pageIndex: page,
            kind: .rowHighlighter,
            rect: rect,
            colourHex: colourHex,
            opacity: 0.35
        )
        annotations.append(created)
        return created
    }
}
