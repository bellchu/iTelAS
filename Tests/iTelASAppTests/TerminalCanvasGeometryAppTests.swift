import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class TerminalCanvasGeometryAppTests: XCTestCase {
    func testTextAdvancesOnTheTerminalCellGrid() throws {
        var screen = TerminalScreen(rows: 24, columns: 80)
        screen.write(
            "MMMMMMMMMM",
            row: 5,
            column: 0,
            attributes: TerminalAttributes(foreground: .green, protected: true)
        )
        screen.cursor.isVisible = false

        let size = CGSize(width: 1_636, height: 516)
        let content = TerminalCanvasView(screen: screen)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let scale = CGFloat(representation.pixelsWide) / host.bounds.width
        var maximumGreenX: Int?
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.greenComponent > 0.55,
                      color.greenComponent > color.redComponent + 0.15,
                      color.greenComponent > color.blueComponent + 0.05 else { continue }
                maximumGreenX = max(maximumGreenX ?? x, x)
            }
        }

        let lastCellOrigin = 18 + 9 * 20
        XCTAssertGreaterThanOrEqual(
            CGFloat(try XCTUnwrap(maximumGreenX)) / scale,
            CGFloat(lastCellOrigin - 2)
        )
    }
}
