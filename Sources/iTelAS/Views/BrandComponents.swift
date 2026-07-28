import SwiftUI

struct ChamferedRectangle: InsettableShape {
    var cut: CGFloat = 5
    private var insetAmount: CGFloat = 0

    init(cut: CGFloat = 5) {
        self.cut = cut
    }

    private init(cut: CGFloat, insetAmount: CGFloat) {
        self.cut = cut
        self.insetAmount = insetAmount
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let corner = min(cut, min(bounds.width, bounds.height) / 3)
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX + corner, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - corner, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + corner))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - corner))
        path.addLine(to: CGPoint(x: bounds.maxX - corner, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX + corner, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - corner))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + corner))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ChamferedRectangle {
        ChamferedRectangle(cut: cut, insetAmount: insetAmount + amount)
    }
}

struct ITelASMark: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height
            let grid = Color.white.opacity(0.11)

            for step in 1...3 {
                let position = CGFloat(step) / 4
                var vertical = Path()
                vertical.move(to: CGPoint(x: width * position, y: height * 0.12))
                vertical.addLine(to: CGPoint(x: width * position, y: height * 0.88))
                context.stroke(vertical, with: .color(grid), lineWidth: 0.65)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: width * 0.12, y: height * position))
                horizontal.addLine(to: CGPoint(x: width * 0.88, y: height * position))
                context.stroke(horizontal, with: .color(grid), lineWidth: 0.65)
            }

            let lineWidth = max(1.4, width * 0.075)
            var dataPath = Path()
            dataPath.move(to: CGPoint(x: width * 0.27, y: height * 0.23))
            dataPath.addLine(to: CGPoint(x: width * 0.27, y: height * 0.76))
            dataPath.addLine(to: CGPoint(x: width * 0.47, y: height * 0.76))
            context.stroke(
                dataPath,
                with: .color(.white.opacity(0.96)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter)
            )

            var terminalPath = Path()
            terminalPath.move(to: CGPoint(x: width * 0.45, y: height * 0.25))
            terminalPath.addLine(to: CGPoint(x: width * 0.78, y: height * 0.25))
            terminalPath.addLine(to: CGPoint(x: width * 0.78, y: height * 0.57))
            terminalPath.addLine(to: CGPoint(x: width * 0.58, y: height * 0.57))
            context.stroke(
                terminalPath,
                with: .color(AppPalette.terminalGreen),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter)
            )

            let node = max(2.2, width * 0.105)
            context.fill(
                Path(CGRect(x: width * 0.27 - node / 2, y: height * 0.23 - node / 2, width: node, height: node)),
                with: .color(AppPalette.registrationBlue)
            )
            context.fill(
                Path(CGRect(x: width * 0.78 - node / 2, y: height * 0.57 - node / 2, width: node, height: node)),
                with: .color(.white)
            )
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
        .background(AppPalette.instrument, in: ChamferedRectangle(cut: size * 0.16))
        .overlay {
            ChamferedRectangle(cut: size * 0.16)
                .stroke(AppPalette.registrationBlue.opacity(0.85), lineWidth: max(0.8, size * 0.035))
        }
        .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            ITelASMark(size: compact ? 27 : 38)
            VStack(alignment: .leading, spacing: 0) {
                Text("iTelAS")
                    .font(.system(size: compact ? 15 : 20, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                    .foregroundStyle(AppPalette.text)
                if !compact {
                    Text("IBM i OPERATIONS WORKBENCH")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.75)
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("iTelAS")
    }
}

enum UtilityGlyphKind {
    case commandCenter
    case commandPalette
    case assistant
    case settings
    case add
    case sessionPulse
    case closeSession
    case copy
    case capture
    case pdfDocument
    case printSnapshot
    case history
    case keyboard
    case paste
    case stage
    case newConversation
    case closePanel
    case send
    case streamRoute
    case stopGeneration
    case provisionalBoundary
    case contextShelf
    case unpinContext
    case patchStack
    case patchMove
    case impactLens
    case outbound
    case connectionTest
}

struct UtilityGlyph: View {
    let kind: UtilityGlyphKind
    var color = AppPalette.secondary
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1.1, w * 0.085), lineCap: .square, lineJoin: .miter)

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], opacity: Double = 1) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
            }

            switch kind {
            case .commandCenter:
                line([point(0.14, 0.38), point(0.14, 0.14), point(0.38, 0.14)])
                line([point(0.62, 0.14), point(0.86, 0.14), point(0.86, 0.38)])
                line([point(0.14, 0.62), point(0.14, 0.86), point(0.38, 0.86)])
                line([point(0.62, 0.86), point(0.86, 0.86), point(0.86, 0.62)])
                context.fill(Path(CGRect(x: w * 0.43, y: h * 0.43, width: w * 0.14, height: h * 0.14)), with: .color(color))
            case .commandPalette:
                line([point(0.12, 0.34), point(0.12, 0.12), point(0.34, 0.12)])
                line([point(0.66, 0.12), point(0.88, 0.12), point(0.88, 0.34)])
                line([point(0.12, 0.66), point(0.12, 0.88), point(0.34, 0.88)])
                line([point(0.66, 0.88), point(0.88, 0.88), point(0.88, 0.66)])
                line([point(0.26, 0.50), point(0.74, 0.50)], opacity: 0.72)
                line([point(0.50, 0.26), point(0.50, 0.74)], opacity: 0.72)
            case .assistant:
                var orbit = Path()
                orbit.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.24, width: w * 0.64, height: h * 0.52))
                context.stroke(orbit, with: .color(color), style: stroke)
                line([point(0.27, 0.70), point(0.18, 0.87), point(0.42, 0.76)])
                context.fill(Path(ellipseIn: CGRect(x: w * 0.34, y: h * 0.43, width: w * 0.08, height: h * 0.08)), with: .color(color))
                context.fill(Path(ellipseIn: CGRect(x: w * 0.58, y: h * 0.43, width: w * 0.08, height: h * 0.08)), with: .color(color))
            case .settings:
                for (index, y) in [0.25, 0.5, 0.75].enumerated() {
                    line([point(0.14, y), point(0.86, y)], opacity: 0.9)
                    let x: CGFloat = [0.36, 0.66, 0.46][index]
                    context.fill(Path(CGRect(x: w * x - w * 0.07, y: h * y - h * 0.07, width: w * 0.14, height: h * 0.14)), with: .color(color))
                }
            case .add:
                line([point(0.5, 0.18), point(0.5, 0.82)])
                line([point(0.18, 0.5), point(0.82, 0.5)])
            case .sessionPulse:
                line([
                    point(0.08, 0.58), point(0.27, 0.58), point(0.39, 0.24),
                    point(0.57, 0.78), point(0.69, 0.44), point(0.92, 0.44)
                ])
                context.fill(
                    Path(CGRect(x: w * 0.04, y: h * 0.54, width: w * 0.08, height: h * 0.08)),
                    with: .color(color.opacity(0.65))
                )
                context.fill(
                    Path(CGRect(x: w * 0.88, y: h * 0.40, width: w * 0.08, height: h * 0.08)),
                    with: .color(color)
                )
            case .closeSession:
                line([point(0.22, 0.22), point(0.78, 0.78)])
                line([point(0.78, 0.22), point(0.22, 0.78)])
                line([point(0.08, 0.34), point(0.08, 0.08), point(0.34, 0.08)], opacity: 0.48)
                line([point(0.66, 0.92), point(0.92, 0.92), point(0.92, 0.66)], opacity: 0.48)
            case .copy:
                var back = Path(CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.54, height: h * 0.54))
                context.stroke(back, with: .color(color.opacity(0.55)), style: stroke)
                back = Path(CGRect(x: w * 0.34, y: h * 0.34, width: w * 0.54, height: h * 0.54))
                context.stroke(back, with: .color(color), style: stroke)
            case .capture:
                let frame = Path(CGRect(x: w * 0.13, y: h * 0.28, width: w * 0.74, height: h * 0.55))
                context.stroke(frame, with: .color(color), style: stroke)
                var lens = Path()
                lens.addEllipse(in: CGRect(x: w * 0.37, y: h * 0.39, width: w * 0.26, height: h * 0.26))
                context.stroke(lens, with: .color(color), style: stroke)
                line([point(0.28, 0.28), point(0.36, 0.16), point(0.61, 0.16), point(0.69, 0.28)])
            case .pdfDocument:
                line([point(0.22, 0.10), point(0.65, 0.10), point(0.82, 0.27), point(0.82, 0.90), point(0.22, 0.90), point(0.22, 0.10)])
                line([point(0.65, 0.10), point(0.65, 0.28), point(0.82, 0.28)], opacity: 0.62)
                line([point(0.34, 0.48), point(0.70, 0.48)], opacity: 0.7)
                line([point(0.34, 0.64), point(0.62, 0.64)], opacity: 0.7)
                context.fill(Path(CGRect(x: w * 0.32, y: h * 0.76, width: w * 0.13, height: h * 0.045)), with: .color(color))
                context.fill(Path(CGRect(x: w * 0.49, y: h * 0.76, width: w * 0.13, height: h * 0.045)), with: .color(color.opacity(0.7)))
            case .printSnapshot:
                line([point(0.28, 0.10), point(0.72, 0.10), point(0.72, 0.34), point(0.28, 0.34), point(0.28, 0.10)])
                line([point(0.18, 0.34), point(0.82, 0.34), point(0.88, 0.44), point(0.88, 0.72), point(0.72, 0.72)])
                line([point(0.28, 0.72), point(0.12, 0.72), point(0.12, 0.44), point(0.18, 0.34)])
                line([point(0.28, 0.59), point(0.72, 0.59), point(0.72, 0.90), point(0.28, 0.90), point(0.28, 0.59)])
                context.fill(Path(CGRect(x: w * 0.72, y: h * 0.43, width: w * 0.07, height: h * 0.07)), with: .color(color))
            case .history:
                var arc = Path()
                arc.addArc(center: point(0.52, 0.52), radius: w * 0.34, startAngle: .degrees(-62), endAngle: .degrees(255), clockwise: false)
                context.stroke(arc, with: .color(color), style: stroke)
                line([point(0.17, 0.53), point(0.16, 0.78), point(0.37, 0.69)])
                line([point(0.52, 0.30), point(0.52, 0.53), point(0.68, 0.62)])
            case .keyboard:
                let body = Path(CGRect(x: w * 0.10, y: h * 0.20, width: w * 0.80, height: h * 0.61))
                context.stroke(body, with: .color(color), style: stroke)
                for y in [0.36, 0.53] {
                    for x in [0.24, 0.41, 0.58, 0.75] {
                        context.fill(
                            Path(CGRect(x: w * x - w * 0.035, y: h * y - h * 0.03, width: w * 0.07, height: h * 0.06)),
                            with: .color(color.opacity(0.78))
                        )
                    }
                }
                line([point(0.27, 0.68), point(0.73, 0.68)], opacity: 0.72)
            case .paste:
                line([point(0.24, 0.22), point(0.24, 0.87), point(0.80, 0.87), point(0.80, 0.22), point(0.64, 0.22)])
                line([point(0.36, 0.22), point(0.36, 0.12), point(0.65, 0.12), point(0.65, 0.32), point(0.36, 0.32), point(0.36, 0.22)])
                line([point(0.37, 0.52), point(0.68, 0.52)], opacity: 0.65)
                line([point(0.37, 0.68), point(0.62, 0.68)], opacity: 0.65)
            case .stage:
                line([point(0.12, 0.20), point(0.48, 0.20), point(0.48, 0.39), point(0.28, 0.39), point(0.28, 0.58), point(0.67, 0.58)])
                line([point(0.52, 0.43), point(0.68, 0.58), point(0.52, 0.73)])
                line([point(0.84, 0.12), point(0.84, 0.88)], opacity: 0.72)
            case .newConversation:
                line([point(0.16, 0.23), point(0.73, 0.23), point(0.73, 0.70), point(0.41, 0.70), point(0.22, 0.86), point(0.22, 0.70), point(0.16, 0.70), point(0.16, 0.23)])
                line([point(0.66, 0.15), point(0.86, 0.15)])
                line([point(0.76, 0.05), point(0.76, 0.25)])
            case .closePanel:
                line([point(0.16, 0.13), point(0.86, 0.13), point(0.86, 0.87), point(0.16, 0.87), point(0.16, 0.13)])
                line([point(0.63, 0.13), point(0.63, 0.87)], opacity: 0.55)
                line([point(0.49, 0.34), point(0.34, 0.50), point(0.49, 0.66)])
            case .send:
                line([point(0.50, 0.84), point(0.50, 0.17)])
                line([point(0.24, 0.43), point(0.50, 0.17), point(0.76, 0.43)])
                line([point(0.22, 0.85), point(0.78, 0.85)], opacity: 0.55)
            case .streamRoute:
                line([point(0.08, 0.24), point(0.32, 0.24), point(0.32, 0.08)])
                line([point(0.32, 0.08), point(0.32, 0.50), point(0.69, 0.50), point(0.69, 0.82), point(0.92, 0.82)])
                line([point(0.51, 0.68), point(0.69, 0.68), point(0.69, 0.50)], opacity: 0.58)
                context.fill(Path(CGRect(x: w * 0.04, y: h * 0.20, width: w * 0.08, height: h * 0.08)), with: .color(color.opacity(0.7)))
                context.fill(Path(CGRect(x: w * 0.88, y: h * 0.78, width: w * 0.08, height: h * 0.08)), with: .color(color))
            case .stopGeneration:
                let back = Path(CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.54, height: h * 0.54))
                let front = Path(CGRect(x: w * 0.34, y: h * 0.34, width: w * 0.54, height: h * 0.54))
                context.stroke(back, with: .color(color.opacity(0.62)), style: stroke)
                context.stroke(front, with: .color(color), style: stroke)
            case .provisionalBoundary:
                line([point(0.24, 0.43), point(0.24, 0.30), point(0.36, 0.16), point(0.64, 0.16), point(0.76, 0.30), point(0.76, 0.43)])
                line([point(0.16, 0.43), point(0.84, 0.43), point(0.84, 0.88), point(0.16, 0.88), point(0.16, 0.43)])
                line([point(0.50, 0.60), point(0.50, 0.73)], opacity: 0.76)
            case .contextShelf:
                line([point(0.18, 0.10), point(0.18, 0.90)])
                line([point(0.18, 0.22), point(0.76, 0.22), point(0.76, 0.38)])
                line([point(0.18, 0.50), point(0.60, 0.50), point(0.60, 0.66)])
                line([point(0.18, 0.78), point(0.84, 0.78)])
                context.fill(Path(CGRect(x: w * 0.72, y: h * 0.34, width: w * 0.08, height: h * 0.08)), with: .color(color))
                context.fill(Path(CGRect(x: w * 0.56, y: h * 0.62, width: w * 0.08, height: h * 0.08)), with: .color(color.opacity(0.7)))
            case .unpinContext:
                line([point(0.20, 0.16), point(0.80, 0.76)])
                line([point(0.80, 0.16), point(0.20, 0.76)])
                line([point(0.12, 0.90), point(0.88, 0.90)], opacity: 0.48)
            case .patchStack:
                line([point(0.18, 0.08), point(0.18, 0.92)])
                line([point(0.18, 0.22), point(0.72, 0.22)])
                line([point(0.18, 0.50), point(0.58, 0.50)])
                line([point(0.18, 0.78), point(0.80, 0.78)])
                line([point(0.72, 0.22), point(0.84, 0.22), point(0.84, 0.78), point(0.80, 0.78)], opacity: 0.56)
                context.fill(Path(CGRect(x: w * 0.68, y: h * 0.18, width: w * 0.08, height: h * 0.08)), with: .color(color))
                context.fill(Path(CGRect(x: w * 0.54, y: h * 0.46, width: w * 0.08, height: h * 0.08)), with: .color(color.opacity(0.72)))
            case .patchMove:
                line([point(0.22, 0.50), point(0.78, 0.50)])
                line([point(0.50, 0.08), point(0.34, 0.24), point(0.66, 0.24), point(0.50, 0.08)])
                line([point(0.50, 0.92), point(0.34, 0.76), point(0.66, 0.76), point(0.50, 0.92)])
                context.fill(Path(CGRect(x: w * 0.43, y: h * 0.43, width: w * 0.14, height: h * 0.14)), with: .color(color))
            case .impactLens:
                var ring = Path()
                ring.addEllipse(in: CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56))
                context.stroke(ring, with: .color(color), style: stroke)
                line([point(0.08, 0.50), point(0.92, 0.50)], opacity: 0.52)
                line([point(0.50, 0.08), point(0.50, 0.92)], opacity: 0.52)
                context.fill(Path(CGRect(x: w * 0.45, y: h * 0.45, width: w * 0.10, height: h * 0.10)), with: .color(color))
            case .outbound:
                line([point(0.18, 0.79), point(0.78, 0.19)])
                line([point(0.43, 0.19), point(0.78, 0.19), point(0.78, 0.54)])
                line([point(0.18, 0.28), point(0.18, 0.82), point(0.72, 0.82)], opacity: 0.5)
            case .connectionTest:
                line([point(0.14, 0.50), point(0.34, 0.50)])
                line([point(0.66, 0.50), point(0.86, 0.50)])
                line([point(0.31, 0.31), point(0.50, 0.50), point(0.31, 0.69)])
                line([point(0.69, 0.31), point(0.50, 0.50), point(0.69, 0.69)])
                context.fill(Path(CGRect(x: w * 0.45, y: h * 0.45, width: w * 0.10, height: h * 0.10)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WorkbenchGlyph: View {
    let tool: WorkbenchTool
    var color = AppPalette.secondary
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1.05, w * 0.065), lineCap: .square, lineJoin: .miter)

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], opacity: Double = 1) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, opacity: Double = 1) {
                context.stroke(Path(CGRect(x: w * x, y: h * y, width: w * width, height: h * height)), with: .color(color.opacity(opacity)), style: stroke)
            }
            func node(_ x: CGFloat, _ y: CGFloat, filled: Bool = true) {
                let rect = CGRect(x: w * x - w * 0.065, y: h * y - h * 0.065, width: w * 0.13, height: h * 0.13)
                if filled { context.fill(Path(rect), with: .color(color)) }
                else { context.stroke(Path(rect), with: .color(color), style: stroke) }
            }

            switch tool {
            case .terminal:
                box(0.08, 0.13, 0.84, 0.67)
                line([p(0.19, 0.34), p(0.31, 0.45), p(0.19, 0.56)])
                line([p(0.39, 0.56), p(0.62, 0.56)])
                line([p(0.35, 0.88), p(0.65, 0.88)])
            case .commandCenter:
                box(0.10, 0.10, 0.32, 0.32)
                box(0.58, 0.10, 0.32, 0.32)
                box(0.10, 0.58, 0.32, 0.32)
                box(0.58, 0.58, 0.32, 0.32)
                node(0.50, 0.50)
            case .sourceWorkspace:
                line([p(0.22, 0.14), p(0.10, 0.14), p(0.10, 0.86), p(0.22, 0.86)])
                line([p(0.78, 0.14), p(0.90, 0.14), p(0.90, 0.86), p(0.78, 0.86)])
                line([p(0.35, 0.29), p(0.65, 0.29)])
                line([p(0.35, 0.50), p(0.74, 0.50)])
                line([p(0.35, 0.71), p(0.57, 0.71)])
            case .sqlStudio:
                var cylinder = Path()
                cylinder.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.10, width: w * 0.68, height: h * 0.25))
                context.stroke(cylinder, with: .color(color), style: stroke)
                line([p(0.16, 0.22), p(0.16, 0.75)])
                line([p(0.84, 0.22), p(0.84, 0.75)])
                var bottom = Path()
                bottom.addArc(center: p(0.50, 0.75), radius: w * 0.34, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                context.stroke(bottom, with: .color(color), style: stroke)
                line([p(0.27, 0.49), p(0.73, 0.49)], opacity: 0.55)
            case .objectGraph:
                line([p(0.22, 0.68), p(0.48, 0.24), p(0.78, 0.67), p(0.22, 0.68)])
                node(0.22, 0.68)
                node(0.48, 0.24, filled: false)
                node(0.78, 0.67)
            case .buildAndTest:
                line([p(0.18, 0.78), p(0.52, 0.44), p(0.72, 0.64)])
                box(0.40, 0.16, 0.43, 0.25)
                line([p(0.63, 0.72), p(0.74, 0.82), p(0.91, 0.60)])
            case .jobsAndQueues:
                for y in [0.23, 0.50, 0.77] {
                    node(0.16, y, filled: false)
                    line([p(0.28, y), p(0.86, y)], opacity: y == 0.50 ? 1 : 0.55)
                }
                line([p(0.46, 0.50), p(0.53, 0.34), p(0.62, 0.66), p(0.70, 0.50)])
            case .spoolAndOutput:
                box(0.17, 0.31, 0.66, 0.48)
                box(0.29, 0.10, 0.42, 0.28, opacity: 0.65)
                line([p(0.31, 0.59), p(0.69, 0.59)])
                line([p(0.31, 0.70), p(0.58, 0.70)])
                node(0.72, 0.43)
            case .transferCenter:
                line([p(0.12, 0.34), p(0.77, 0.34), p(0.64, 0.20)])
                line([p(0.88, 0.66), p(0.23, 0.66), p(0.36, 0.80)])
                node(0.12, 0.34, filled: false)
                node(0.88, 0.66, filled: false)
            case .systemHealth:
                var ring = Path()
                ring.addEllipse(in: CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.76, height: h * 0.76))
                context.stroke(ring, with: .color(color.opacity(0.55)), style: stroke)
                line([p(0.22, 0.55), p(0.37, 0.55), p(0.45, 0.34), p(0.56, 0.70), p(0.65, 0.49), p(0.80, 0.49)])
            case .automation:
                line([p(0.24, 0.30), p(0.72, 0.30), p(0.83, 0.43)])
                line([p(0.76, 0.70), p(0.28, 0.70), p(0.17, 0.57)])
                node(0.24, 0.30)
                node(0.76, 0.70, filled: false)
                var play = Path()
                play.move(to: p(0.45, 0.42))
                play.addLine(to: p(0.65, 0.52))
                play.addLine(to: p(0.45, 0.62))
                play.closeSubpath()
                context.stroke(play, with: .color(color), style: stroke)
            case .securityAdvisor:
                // A compact access-route lattice: one subject fans through
                // independent evidence paths before converging on one object.
                line([p(0.12, 0.50), p(0.29, 0.50)])
                line([p(0.29, 0.50), p(0.47, 0.22), p(0.67, 0.22), p(0.84, 0.50)])
                line([p(0.29, 0.50), p(0.50, 0.50), p(0.84, 0.50)], opacity: 0.68)
                line([p(0.29, 0.50), p(0.47, 0.78), p(0.67, 0.78), p(0.84, 0.50)])
                node(0.12, 0.50)
                node(0.50, 0.50, filled: false)
                node(0.84, 0.50)
                var decision = Path()
                decision.move(to: p(0.50, 0.39))
                decision.addLine(to: p(0.61, 0.50))
                decision.addLine(to: p(0.50, 0.61))
                decision.addLine(to: p(0.39, 0.50))
                decision.closeSubpath()
                context.stroke(decision, with: .color(color), style: stroke)
            case .casebook:
                line([p(0.10, 0.27), p(0.38, 0.27), p(0.50, 0.50), p(0.68, 0.50), p(0.88, 0.73)])
                line([p(0.10, 0.73), p(0.38, 0.73), p(0.50, 0.50), p(0.68, 0.50), p(0.88, 0.27)], opacity: 0.62)
                node(0.10, 0.27)
                node(0.10, 0.73, filled: false)
                node(0.50, 0.50, filled: false)
                node(0.88, 0.27)
                node(0.88, 0.73, filled: false)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PrecisionIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(configuration.isPressed ? AppPalette.registrationBlue.opacity(0.12) : Color.clear)
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(configuration.isPressed ? AppPalette.registrationBlue : AppPalette.borderStrong, lineWidth: 0.8)
            }
            .contentShape(ChamferedRectangle(cut: 4))
    }
}
