import Foundation
import SwiftUI
import iTelASCore

struct TerminalFunctionKeyLayoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let profile: SessionProfile

    @State private var bindings: [TerminalFunctionKeyBinding]
    @State private var selectedSlot: Int

    init(profile: SessionProfile) {
        self.profile = profile
        let initial = Self.normalized(profile.functionKeyBindings)
        _bindings = State(initialValue: initial)
        _selectedSlot = State(initialValue: initial.first(where: \.isPinned)?.slot ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 18) {
                commandPad
                inspector
                    .frame(width: 344)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .frame(width: 1_080, height: 720)
        .background(AppPalette.window)
    }

    private var header: some View {
        HStack(spacing: 12) {
            UtilityGlyph(kind: .keyboard, color: AppPalette.terminal(.turquoise), size: 18)
                .frame(width: 34, height: 34)
                .background(AppPalette.terminalRaised, in: ChamferedRectangle(cut: 4))
                .overlay {
                    ChamferedRectangle(cut: 4)
                        .stroke(AppPalette.registrationBlue.opacity(0.75), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(profile.name.uppercased()) · PROFILE SETTINGS")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                    .lineLimit(1)
                Text("Function key layout")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(AppPalette.success)
                    .frame(width: 7, height: 7)
                Text("PROFILE-SCOPED · 24 KEYS")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(AppPalette.success)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppPalette.success.opacity(0.08), in: ChamferedRectangle(cut: 3))
            .overlay {
                ChamferedRectangle(cut: 3)
                    .stroke(AppPalette.success.opacity(0.25), lineWidth: 1)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 76)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var commandPad: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text("COMMAND PAD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Choose the key an operator reaches for. Its host AID and plain-language label stay with this profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(bindings) { binding in
                    keyCard(binding)
                }
            }
            .padding(14)
            .background(AppPalette.panel, in: ChamferedRectangle(cut: 5))
            .overlay {
                ChamferedRectangle(cut: 5)
                    .stroke(AppPalette.borderStrong, lineWidth: 1)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Hardware F1–F12 and Shift-F1–F12 remain visible. Remapping changes only the host function AID; host-controlled field-data rules are preserved.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.ibmBlue.opacity(0.06), in: ChamferedRectangle(cut: 4))
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(AppPalette.ibmBlue.opacity(0.18), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func keyCard(_ binding: TerminalFunctionKeyBinding) -> some View {
        let selected = binding.slot == selectedSlot
        return Button {
            selectedSlot = binding.slot
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(binding.physicalKeyLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.text)
                    Spacer(minLength: 0)
                    if binding.isPinned {
                        Circle()
                            .fill(selected ? AppPalette.ibmBlue : AppPalette.success)
                            .frame(width: 5, height: 5)
                    }
                }

                Text(binding.displayLabel)
                    .font(.system(size: 9.5, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? AppPalette.text : AppPalette.secondary)
                    .lineLimit(1)

                Text("AID \(binding.hostActionLabel)")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 73, alignment: .leading)
            .background(
                selected ? AppPalette.selection : AppPalette.raised,
                in: ChamferedRectangle(cut: 4)
            )
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(selected ? AppPalette.ibmBlue : AppPalette.border, lineWidth: selected ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(binding.physicalKeyLabel), sends host \(binding.hostActionLabel), \(binding.displayLabel)"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SELECTED KEY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppPalette.ibmBlue)

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedBinding.physicalKeyLabel)
                    .font(.system(size: 21, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.terminalGreen)
                Text("HARDWARE \(selectedBinding.physicalKeyLabel) → HOST AID \(selectedBinding.hostActionLabel)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(AppPalette.terminal(.turquoise))
                Text(selectedBinding.isPinned ? "Pinned in terminal dock" : "Hidden from terminal dock")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.64))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.terminalRaised, in: ChamferedRectangle(cut: 4))

            inspectorField("HOST ACTION") {
                Menu {
                    ForEach(TerminalFunctionKeyBinding.slotRange, id: \.self) { number in
                        Button("F\(number) · \(TerminalFunctionKeyBinding.defaultLabel(for: number))") {
                            selectedHostFunction.wrappedValue = number
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("\(selectedBinding.hostActionLabel) · \(TerminalFunctionKeyBinding.defaultLabel(for: selectedBinding.hostFunction))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppPalette.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(AppPalette.raised, in: ChamferedRectangle(cut: 3))
                    .overlay {
                        ChamferedRectangle(cut: 3)
                            .stroke(AppPalette.borderStrong, lineWidth: 0.8)
                    }
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Host function action")
            }

            inspectorField("DOCK LABEL") {
                TextField("Host key", text: selectedLabel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Function key dock label")
            }

            inspectorField("TERMINAL DOCK") {
                HStack(spacing: 8) {
                    Text(selectedBinding.isPinned ? "Pinned · shown in terminal dock" : "Hidden from terminal dock")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                    Spacer()
                    Toggle("Pin this key in the terminal dock", isOn: selectedPinned)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if let firstError = validationErrors.first {
                Label(firstError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRANSPORT BOUNDARY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.muted)
                Text("Changing this layout never opens a connection or sends a host key.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(AppPalette.border, lineWidth: 1)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppPalette.panel, in: ChamferedRectangle(cut: 5))
        .overlay {
            ChamferedRectangle(cut: 5)
                .stroke(AppPalette.borderStrong, lineWidth: 1)
        }
    }

    private func inspectorField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Identity layout by default · saved only with this session profile")
                .font(.system(size: 9.5))
                .foregroundStyle(AppPalette.secondary)

            Spacer()

            Button("Restore defaults") {
                bindings = TerminalFunctionKeyBinding.standard
                selectedSlot = 1
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Save layout") {
                save()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!validationErrors.isEmpty)
        }
        .padding(.horizontal, 26)
        .frame(height: 66)
        .background(AppPalette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var selectedBinding: TerminalFunctionKeyBinding {
        bindings.first(where: { $0.slot == selectedSlot })
            ?? TerminalFunctionKeyBinding.standard[0]
    }

    private var selectedHostFunction: Binding<Int> {
        Binding(
            get: { selectedBinding.hostFunction },
            set: { value in updateSelected { $0.hostFunction = value } }
        )
    }

    private var selectedLabel: Binding<String> {
        Binding(
            get: { selectedBinding.label },
            set: { value in
                let visible = value.unicodeScalars.filter {
                    !CharacterSet.controlCharacters.contains($0)
                }
                updateSelected {
                    $0.label = String(
                        String(String.UnicodeScalarView(visible))
                            .prefix(TerminalFunctionKeyBinding.maximumLabelLength)
                    )
                }
            }
        )
    }

    private var selectedPinned: Binding<Bool> {
        Binding(
            get: { selectedBinding.isPinned },
            set: { value in updateSelected { $0.isPinned = value } }
        )
    }

    private var validationErrors: [String] {
        TerminalFunctionKeyBinding.validationErrors(for: bindings)
    }

    private func updateSelected(_ update: (inout TerminalFunctionKeyBinding) -> Void) {
        guard let index = bindings.firstIndex(where: { $0.slot == selectedSlot }) else { return }
        var changed = bindings
        update(&changed[index])
        bindings = changed
    }

    private func save() {
        guard validationErrors.isEmpty else { return }
        var updated = profile
        updated.functionKeyBindings = bindings.sorted { $0.slot < $1.slot }
        model.saveProfile(updated)
        model.showNotice("Saved the profile-scoped 5250 function-key layout for \(profile.name).")
        dismiss()
    }

    private static func normalized(
        _ bindings: [TerminalFunctionKeyBinding]
    ) -> [TerminalFunctionKeyBinding] {
        guard TerminalFunctionKeyBinding.validationErrors(for: bindings).isEmpty else {
            return TerminalFunctionKeyBinding.standard
        }
        return bindings.sorted { $0.slot < $1.slot }
    }
}
