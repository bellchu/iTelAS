import SwiftUI

struct ScreenHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        HStack(spacing: 0) {
            timeline
                .frame(width: 280)
            Rectangle().fill(AppPalette.border).frame(width: 1)
            preview
        }
        .background(AppPalette.window)
        .onAppear {
            selectedID = model.screenHistory.last?.id
            proverb = .random(excluding: proverb.id)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCREEN HISTORY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Session timeline")
                    .font(.system(size: 18, weight: .bold))
                Text("Up to 100 in-memory screens · never sent to AI automatically")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                Text("\(proverb.text) — \(proverb.source)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(model.screenHistory.reversed()) { snapshot in
                        Button {
                            selectedID = snapshot.id
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(snapshot.id == selectedID ? AppPalette.ibmBlue : AppPalette.border)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snapshot.title)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(AppPalette.text)
                                        .lineLimit(1)
                                    Text("\(snapshot.source) · \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(snapshot.id == selectedID ? AppPalette.ibmBlue.opacity(0.08) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .background(AppPalette.panel)
    }

    @ViewBuilder
    private var preview: some View {
        if let snapshot = model.screenHistory.first(where: { $0.id == selectedID }) ?? model.screenHistory.last {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text("\(snapshot.screen.rows)×\(snapshot.screen.columns) · captured \(snapshot.capturedAt.formatted())")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer()
                    Button("Copy") { model.copyVisibleScreen(snapshot.screen) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        model.captureScreen(snapshot.screen)
                    } label: {
                        HStack(spacing: 6) {
                            UtilityGlyph(kind: .capture, color: .white, size: 12)
                            Text("Export PNG")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        model.exportScreenPDF(snapshot.screen)
                    } label: {
                        HStack(spacing: 6) {
                            UtilityGlyph(kind: .pdfDocument, color: AppPalette.text, size: 12)
                            Text("PDF")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        model.printScreenSnapshot(snapshot.screen)
                    } label: {
                        UtilityGlyph(kind: .printSnapshot, color: AppPalette.text, size: 14)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Print this redacted screen snapshot")
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background(AppPalette.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                Panel {
                    TerminalCanvasView(screen: snapshot.screen)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("No screen history", systemImage: "clock.arrow.circlepath")
        }
    }
}
