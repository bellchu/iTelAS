import SwiftUI

struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = AIConfiguration()
    @State private var apiKey = ""
    @State private var saveError: String?
    @State private var proverb = WorkbenchProverb.random()
    @State private var confirmsKeyDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    enableCard
                    providerFields
                    contextPolicy
                    ProverbRibbon(proverb: proverb)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
                    if draft.isEnabled {
                        ForEach(draft.validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.warning)
                        }
                        if !model.apiKeyExists && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("An API key is required before AI Assist can be enabled.", systemImage: "key.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.warning)
                        }
                    }
                    if let saveError {
                        Label(saveError, systemImage: "xmark.octagon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.danger)
                    }
                }
                .padding(22)
            }
            actions
        }
        .background(AppPalette.panel)
        .onAppear {
            draft = model.aiConfiguration
            apiKey = ""
            proverb = .random(excluding: proverb.id)
        }
        .alert("Forget the stored API key?", isPresented: $confirmsKeyDeletion) {
            Button("Forget Key", role: .destructive) {
                do {
                    try model.forgetAPIKey()
                    apiKey = ""
                } catch {
                    saveError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The provider key will be removed from macOS Keychain. AI Assist will stop working until a new key is saved.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ITelASMark(size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Assist Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Opt in deliberately. Your key stays in macOS Keychain.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 70)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var enableCard: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.isEnabled ? "checkmark.shield.fill" : "shield")
                .foregroundStyle(draft.isEnabled ? AppPalette.success : AppPalette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable iTelAS Assist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("Nothing is sent until you ask; no suggested command executes automatically.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Toggle("Enable", isOn: $draft.isEnabled).labelsHidden().toggleStyle(.switch)
        }
        .padding(13)
        .background(AppPalette.success.opacity(0.065), in: ChamferedRectangle(cut: 5))
        .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.success.opacity(0.18), lineWidth: 1) }
    }

    private var providerFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PROVIDER")
            SettingsField(label: "OpenAI-compatible endpoint") {
                TextField("https://api.openai.com/v1/chat/completions", text: $draft.endpoint)
            }
            .disabled(!draft.isEnabled)
            SettingsField(label: "Model") {
                TextField("Provider model name", text: $draft.model)
            }
            .disabled(!draft.isEnabled)
            SettingsField(label: "API key") {
                SecureField(model.apiKeyExists ? "Stored in Keychain" : "Paste API key", text: $apiKey)
            }
            .disabled(!draft.isEnabled)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("The key is stored as a device-only Keychain item. It is never written to preferences, logs, prompts, or the project.", systemImage: "key.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                Spacer(minLength: 8)
                if model.apiKeyExists {
                    Button("Forget stored key") {
                        confirmsKeyDeletion = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.danger)
                }
            }
        }
    }

    private var contextPolicy: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("CONTEXT POLICY")
            Picker("Automatic context", selection: $draft.contextMode) {
                ForEach(AIContextMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Label(
                draft.contextMode == .visibleScreen
                    ? "Only the current visible screen is eligible. Non-display fields and likely credential lines are redacted first."
                    : "Only your typed question and this conversation are sent.",
                systemImage: "eye.slash.fill"
            )
            .font(.system(size: 9))
            .foregroundStyle(AppPalette.secondary)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
        }
        .disabled(!draft.isEnabled)
    }

    private var actions: some View {
        HStack {
            Text("HTTPS is required except for a localhost development endpoint.")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.secondary)
            Button("Save") {
                do {
                    let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    try model.updateAIConfiguration(draft, apiKey: normalizedKey.isEmpty ? nil : normalizedKey)
                    dismiss()
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(AppPalette.muted)
    }

    private var canSave: Bool {
        guard draft.validationErrors.isEmpty else { return false }
        guard draft.isEnabled else { return true }
        return model.apiKeyExists || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SettingsField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppPalette.secondary)
            content
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 37)
                .background(AppPalette.panel, in: ChamferedRectangle(cut: 3))
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.border, lineWidth: 1) }
        }
    }
}
