import SwiftUI
import iTelASCore

enum AppPalette {
    static let window = Color(red: 0.969, green: 0.973, blue: 0.98)
    static let panel = Color.white
    static let raised = Color(red: 0.945, green: 0.957, blue: 0.969)
    static let border = Color(red: 0.867, green: 0.886, blue: 0.906)
    static let text = Color(red: 0.086, green: 0.102, blue: 0.114)
    static let secondary = Color(red: 0.361, green: 0.4, blue: 0.439)
    static let muted = Color(red: 0.494, green: 0.533, blue: 0.573)
    static let ibmBlue = Color(red: 0.059, green: 0.384, blue: 0.996)
    static let registrationBlue = Color(red: 0.067, green: 0.45, blue: 0.88)
    static let instrument = Color(red: 0.055, green: 0.078, blue: 0.098)
    static let borderStrong = Color(red: 0.69, green: 0.73, blue: 0.77)
    static let selection = Color(red: 0.914, green: 0.949, blue: 0.992)
    static let terminal = Color(red: 0.027, green: 0.075, blue: 0.059)
    static let terminalRaised = Color(red: 0.043, green: 0.114, blue: 0.086)
    static let terminalGreen = Color(red: 0.447, green: 0.961, blue: 0.616)
    static let success = Color(red: 0.141, green: 0.631, blue: 0.282)
    static let warning = Color(red: 0.945, green: 0.761, blue: 0.106)
    static let danger = Color(red: 0.855, green: 0.118, blue: 0.157)

    static func environment(_ environment: IBMEnvironment) -> Color {
        switch environment {
        case .development: ibmBlue
        case .qualityAssurance: Color(red: 0.55, green: 0.32, blue: 0.86)
        case .staging: Color(red: 0.72, green: 0.48, blue: 0.04)
        case .production: danger
        }
    }

    static func terminal(_ color: TerminalColor) -> Color {
        switch color {
        case .green: terminalGreen
        case .white: Color(red: 0.91, green: 0.97, blue: 0.93)
        case .red: Color(red: 1, green: 0.45, blue: 0.45)
        case .turquoise: Color(red: 0.47, green: 0.66, blue: 1)
        case .yellow: Color(red: 1, green: 0.84, blue: 0.35)
        case .pink: Color(red: 1, green: 0.55, blue: 0.84)
        case .blue: Color(red: 0.35, green: 0.55, blue: 1)
        case .neutral: Color(red: 0.56, green: 0.71, blue: 0.63)
        case .black: Color(red: 0.008, green: 0.014, blue: 0.018)
        }
    }
}

struct Panel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(AppPalette.panel)
            .clipShape(ChamferedRectangle(cut: 5))
            .overlay {
                ChamferedRectangle(cut: 5)
                    .stroke(AppPalette.border, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 2) {
                    Rectangle().fill(AppPalette.registrationBlue).frame(width: 13, height: 1)
                    Rectangle().fill(AppPalette.registrationBlue.opacity(0.35)).frame(width: 5, height: 1)
                }
                .padding(.leading, 8)
                .padding(.top, 1)
            }
    }
}

struct EnvironmentBadge: View {
    let environment: IBMEnvironment

    var body: some View {
        Text(environment.label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppPalette.environment(environment), in: ChamferedRectangle(cut: 3))
            .overlay {
                ChamferedRectangle(cut: 3)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.6)
            }
            .accessibilityLabel("\(environment.label) environment")
    }
}

struct ProverbRibbon: View {
    let proverb: WorkbenchProverb
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text("PROVERB")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(proverb.text)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(compact ? 1 : 2)
                if !compact {
                    Text("\(proverb.source) · \(proverb.lesson)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workbench proverb: \(proverb.text) Source: \(proverb.source)")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(AppPalette.registrationBlue.opacity(configuration.isPressed ? 0.78 : 1), in: ChamferedRectangle(cut: 5))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppPalette.terminalGreen)
                    .frame(width: 2, height: 22)
                    .padding(.leading, 2)
            }
            .overlay {
                ChamferedRectangle(cut: 5)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
            }
            .contentShape(ChamferedRectangle(cut: 5))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppPalette.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .clipShape(ChamferedRectangle(cut: 4))
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(configuration.isPressed ? AppPalette.registrationBlue : AppPalette.borderStrong, lineWidth: 0.8)
            }
    }
}
