import Foundation
import iTelASCore

struct TerminalSnapshot: Identifiable, Equatable {
    let id: UUID
    let capturedAt: Date
    let source: String
    let screen: TerminalScreen

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        source: String,
        screen: TerminalScreen
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.source = source
        self.screen = screen
    }

    var title: String {
        (0..<screen.rows)
            .lazy
            .map { screen.rowText($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "5250 screen"
    }
}
