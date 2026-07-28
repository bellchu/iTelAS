import AppKit
import Foundation
import UniformTypeIdentifiers
import iTelASCore

@MainActor
struct TerminalExportService {
    func copyText(_ screen: TerminalScreen) {
        copyString(screen.visibleText())
    }

    func copyString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func saveText(
        _ text: String,
        suggestedName: String,
        panelTitle: String = "Export Text Artifact",
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = sanitized(suggestedName) + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data = text.data(using: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func saveJSON(
        _ text: String,
        suggestedName: String,
        panelTitle: String = "Export Handoff Snapshot",
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = sanitized(suggestedName) + ".json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data = text.data(using: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func saveSQLTypedExport(
        _ plan: SQLTypedExportPlan,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = plan.format == .csvBundle
            ? "Save Db2 CSV and Manifest Package"
            : "Save Typed Db2 Result"
        panel.nameFieldStringValue = sanitized(plan.suggestedBaseName)
            + (plan.format == .csvBundle ? ".itelasdb2" : ".typed.json")
        panel.allowedContentTypes = plan.format == .csvBundle
            ? [UTType(exportedAs: "io.situ.itelas.db2-export")]
            : [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let saved = try SQLTypedExportWriter().write(
                    plan,
                    to: url,
                    replacingExisting: true
                )
                completion(.success(saved))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func savePNG(
        _ screen: TerminalScreen,
        suggestedName: String,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Capture 5250 Screen"
        panel.nameFieldStringValue = sanitized(suggestedName) + ".png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try pngData(for: screen).write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func savePDF(
        _ screen: TerminalScreen,
        suggestedName: String,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Export Redacted 5250 Screen"
        panel.nameFieldStringValue = sanitized(suggestedName) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let view = printView(for: screen, title: suggestedName)
                let data = view.dataWithPDF(inside: view.bounds)
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    @discardableResult
    func printSnapshot(_ screen: TerminalScreen, suggestedName: String) -> Bool {
        let view = printView(for: screen, title: suggestedName)
        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return false }
        printInfo.orientation = screen.columns > 80 ? .landscape : .portrait
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = "iTelAS — \(suggestedName)"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
    }

    func pngData(for screen: TerminalScreen) throws -> Data {
        let cellSize = CGSize(width: 10, height: 18)
        let inset: CGFloat = 22
        let size = CGSize(
            width: CGFloat(screen.columns) * cellSize.width + inset * 2,
            height: CGFloat(screen.rows) * cellSize.height + inset * 2
        )
        let image = NSImage(size: size, flipped: true) { bounds in
            NSColor(calibratedRed: 0.027, green: 0.075, blue: 0.059, alpha: 1).setFill()
            bounds.fill()
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            let intenseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

            for row in 0..<screen.rows {
                for column in 0..<screen.columns {
                    let cell = screen.cells[row * screen.columns + column]
                    let cellRect = CGRect(
                        x: inset + CGFloat(column) * cellSize.width,
                        y: inset + CGFloat(row) * cellSize.height,
                        width: cellSize.width,
                        height: cellSize.height
                    )
                    let foreground = nsColor(for: cell.attributes.foreground)
                    if cell.attributes.reverse {
                        foreground.setFill()
                        cellRect.fill()
                    }
                    if cell.attributes.columnSeparator {
                        foreground.withAlphaComponent(0.4).setStroke()
                        let separator = NSBezierPath()
                        separator.lineWidth = 0.65
                        separator.move(to: CGPoint(x: cellRect.minX, y: cellRect.minY + 3))
                        separator.line(to: CGPoint(x: cellRect.minX, y: cellRect.maxY - 3))
                        if column == screen.columns - 1 {
                            separator.move(to: CGPoint(x: cellRect.maxX, y: cellRect.minY + 3))
                            separator.line(to: CGPoint(x: cellRect.maxX, y: cellRect.maxY - 3))
                        }
                        separator.stroke()
                    }
                    let character = cell.attributes.nonDisplay ? " " : String(cell.character)
                    let style = NSMutableParagraphStyle()
                    style.alignment = .left
                    var textAttributes: [NSAttributedString.Key: Any] = [
                        .font: cell.attributes.highIntensity ? intenseFont : font,
                        .foregroundColor: cell.attributes.reverse
                            ? NSColor(calibratedRed: 0.027, green: 0.075, blue: 0.059, alpha: 1)
                            : foreground,
                        .paragraphStyle: style
                    ]
                    if cell.attributes.underline {
                        textAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    }
                    (character as NSString).draw(at: cellRect.origin, withAttributes: textAttributes)
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return result.isEmpty ? "itelas-screen" : result
    }

    private func printView(for screen: TerminalScreen, title: String) -> TerminalSnapshotPrintView {
        TerminalSnapshotPrintView(screen: screen, title: title)
    }

    private func nsColor(for color: TerminalColor) -> NSColor {
        switch color {
        case .green: NSColor(calibratedRed: 0.447, green: 0.961, blue: 0.616, alpha: 1)
        case .white: NSColor(calibratedRed: 0.91, green: 0.97, blue: 0.93, alpha: 1)
        case .red: NSColor(calibratedRed: 1, green: 0.45, blue: 0.45, alpha: 1)
        case .turquoise: NSColor(calibratedRed: 0.47, green: 0.66, blue: 1, alpha: 1)
        case .yellow: NSColor(calibratedRed: 1, green: 0.84, blue: 0.35, alpha: 1)
        case .pink: NSColor(calibratedRed: 1, green: 0.55, blue: 0.84, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.35, green: 0.55, blue: 1, alpha: 1)
        case .neutral: NSColor(calibratedRed: 0.56, green: 0.71, blue: 0.63, alpha: 1)
        case .black: NSColor(calibratedWhite: 0.005, alpha: 1)
        }
    }
}

@MainActor
private final class TerminalSnapshotPrintView: NSView {
    private let screen: TerminalScreen
    private let documentTitle: String
    private let cellSize = CGSize(width: 7.7, height: 13.6)
    private let horizontalInset: CGFloat = 25
    private let topInset: CGFloat = 66
    private let bottomInset: CGFloat = 25

    init(screen: TerminalScreen, title: String) {
        self.screen = screen
        documentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "5250 screen"
            : title
        let size = CGSize(
            width: CGFloat(screen.columns) * cellSize.width + horizontalInset * 2,
            height: CGFloat(screen.rows) * cellSize.height + topInset + bottomInset
        )
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let header = CGRect(x: 0, y: 0, width: bounds.width, height: topInset - 10)
        NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.095, alpha: 1).setFill()
        header.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        ("iTelAS  /  5250 SCREEN SNAPSHOT" as NSString).draw(
            at: CGPoint(x: horizontalInset, y: 12),
            withAttributes: titleAttributes
        )

        let detail = "\(documentTitle)   ·   \(screen.rows)×\(screen.columns)   ·   \(Date().formatted(date: .abbreviated, time: .standard))"
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1)
        ]
        (detail as NSString).draw(
            at: CGPoint(x: horizontalInset, y: 34),
            withAttributes: detailAttributes
        )

        let terminalBounds = CGRect(
            x: horizontalInset - 8,
            y: topInset - 8,
            width: CGFloat(screen.columns) * cellSize.width + 16,
            height: CGFloat(screen.rows) * cellSize.height + 16
        )
        NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
        terminalBounds.fill()
        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        NSBezierPath(rect: terminalBounds).stroke()

        let font = NSFont.monospacedSystemFont(ofSize: 9.4, weight: .medium)
        let intenseFont = NSFont.monospacedSystemFont(ofSize: 9.4, weight: .bold)
        for row in 0..<screen.rows {
            for column in 0..<screen.columns {
                let cell = screen.cells[row * screen.columns + column]
                let cellRect = CGRect(
                    x: horizontalInset + CGFloat(column) * cellSize.width,
                    y: topInset + CGFloat(row) * cellSize.height,
                    width: cellSize.width,
                    height: cellSize.height
                )
                let foreground = printColor(for: cell.attributes.foreground)
                if cell.attributes.reverse {
                    foreground.setFill()
                    cellRect.fill()
                }
                if cell.attributes.columnSeparator {
                    foreground.withAlphaComponent(0.42).setStroke()
                    let separator = NSBezierPath()
                    separator.lineWidth = 0.55
                    separator.move(to: CGPoint(x: cellRect.minX, y: cellRect.minY + 2))
                    separator.line(to: CGPoint(x: cellRect.minX, y: cellRect.maxY - 2))
                    if column == screen.columns - 1 {
                        separator.move(to: CGPoint(x: cellRect.maxX, y: cellRect.minY + 2))
                        separator.line(to: CGPoint(x: cellRect.maxX, y: cellRect.maxY - 2))
                    }
                    separator.stroke()
                }
                let character = cell.attributes.nonDisplay ? " " : String(cell.character)
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: cell.attributes.highIntensity ? intenseFont : font,
                    .foregroundColor: cell.attributes.reverse ? NSColor.white : foreground
                ]
                if cell.attributes.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                (character as NSString).draw(at: cellRect.origin, withAttributes: attributes)
            }
        }

        let footer = "Non-display fields are suppressed. This snapshot is a local operator artifact; no host input or AI request was generated."
        (footer as NSString).draw(
            at: CGPoint(x: horizontalInset, y: bounds.height - 17),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 7.4, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1)
            ]
        )
    }

    private func printColor(for color: TerminalColor) -> NSColor {
        switch color {
        case .green: NSColor(calibratedRed: 0.05, green: 0.36, blue: 0.19, alpha: 1)
        case .white, .neutral: NSColor(calibratedWhite: 0.12, alpha: 1)
        case .red: NSColor(calibratedRed: 0.70, green: 0.12, blue: 0.10, alpha: 1)
        case .turquoise: NSColor(calibratedRed: 0.02, green: 0.37, blue: 0.47, alpha: 1)
        case .yellow: NSColor(calibratedRed: 0.53, green: 0.38, blue: 0.02, alpha: 1)
        case .pink: NSColor(calibratedRed: 0.57, green: 0.12, blue: 0.43, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.12, green: 0.29, blue: 0.66, alpha: 1)
        case .black: NSColor.black
        }
    }
}
