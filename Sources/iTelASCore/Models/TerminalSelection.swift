import Foundation

public struct TerminalSelectionPoint: Equatable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public struct TerminalSelection: Equatable, Sendable {
    public let anchor: TerminalSelectionPoint
    public let extent: TerminalSelectionPoint

    public init(anchor: TerminalSelectionPoint, extent: TerminalSelectionPoint) {
        self.anchor = anchor
        self.extent = extent
    }

    public var minimumRow: Int { min(anchor.row, extent.row) }
    public var maximumRow: Int { max(anchor.row, extent.row) }
    public var minimumColumn: Int { min(anchor.column, extent.column) }
    public var maximumColumn: Int { max(anchor.column, extent.column) }
    public var selectedRowCount: Int { maximumRow - minimumRow + 1 }
    public var selectedColumnCount: Int { maximumColumn - minimumColumn + 1 }

    public func contains(row: Int, column: Int) -> Bool {
        (minimumRow...maximumRow).contains(row)
            && (minimumColumn...maximumColumn).contains(column)
    }

    public func text(from screen: TerminalScreen) -> String {
        let firstRow = max(0, minimumRow)
        let lastRow = min(screen.rows - 1, maximumRow)
        let firstColumn = max(0, minimumColumn)
        let lastColumn = min(screen.columns - 1, maximumColumn)
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return "" }

        return (firstRow...lastRow).map { row in
            var line = String((firstColumn...lastColumn).map { column in
                let cell = screen.cells[row * screen.columns + column]
                return cell.attributes.nonDisplay ? " " : cell.character
            })
            while line.last == " " { line.removeLast() }
            return line
        }.joined(separator: "\n")
    }
}
