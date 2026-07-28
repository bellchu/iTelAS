import AppKit
import SwiftUI
import iTelASCore

struct CompileRecipeStudioView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                recipeLibrary
                    .frame(width: 232)
                buildWorkbench
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                evidenceRail
                    .frame(width: 284)
            }
            footer
        }
        .frame(width: 1_180, height: 760)
        .background(AppPalette.window)
        .onAppear {
            model.rotateProverb()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CompileRecipeSpindleMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("DELIVERY / RECIPE SPINDLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Compile Recipe Studio")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            recipeModeBadge
            EnvironmentBadge(environment: model.compileRecipeDraft.environment)
            Button {
                model.createCompileRecipeDraft()
            } label: {
                Label("New recipe", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            Button {
                model.duplicateCompileRecipeDraft()
            } label: {
                Label("Duplicate", systemImage: "square.on.square")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.compileRecipePreview == nil)
            Button {
                model.saveCompileRecipe()
            } label: {
                Label("Save recipe", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.compileRecipePreview == nil || model.compileRecipeDraftIsSaved)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var recipeModeBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.compileRecipeUsesBundledDefaults ? AppPalette.warning : AppPalette.success)
                .frame(width: 6, height: 6)
            Text(model.compileRecipeUsesBundledDefaults ? "BUNDLED EXAMPLES" : "LOCAL LIBRARY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.45)
        }
        .foregroundStyle(model.compileRecipeUsesBundledDefaults ? AppPalette.warning : AppPalette.success)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(
            (model.compileRecipeUsesBundledDefaults ? AppPalette.warning : AppPalette.success).opacity(0.08)
        )
        .clipShape(ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3)
                .stroke(model.compileRecipeUsesBundledDefaults ? AppPalette.warning : AppPalette.success, lineWidth: 0.8)
        }
    }

    private var recipeLibrary: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECIPE LIBRARY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("\(model.compileRecipeLibrary.recipes.count) repeatable builds")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                RecipeRouteGlyph(color: AppPalette.registrationBlue, size: 20)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                TextField("Name, source, target", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRecipes) { recipe in
                        Button {
                            model.selectCompileRecipe(recipe.id)
                        } label: {
                            recipeRow(recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LOCAL CUSTODY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                Label("Permission-restricted JSON", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("No password, API key, source body, or host response is stored.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineSpacing(2)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }
        }
        .background(AppPalette.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppPalette.border).frame(width: 1)
        }
    }

    private var filteredRecipes: [CompileRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.compileRecipeLibrary.recipes }
        return model.compileRecipeLibrary.recipes.filter {
            [$0.name, $0.sourceIdentity, $0.targetIdentity, $0.toolchain.languageLabel]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private func recipeRow(_ recipe: CompileRecipe) -> some View {
        let selected = recipe.id == model.selectedCompileRecipeID
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(recipe.toolchain.languageLabel)
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
                Spacer()
                Circle()
                    .fill(AppPalette.environment(recipe.environment))
                    .frame(width: 6, height: 6)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            Text(recipe.name)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
            Text(recipe.sourceIdentity)
                .font(.system(size: 8.2, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? AppPalette.selection : AppPalette.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(selected ? AppPalette.ibmBlue : Color.clear)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var buildWorkbench: some View {
        VStack(spacing: 0) {
            workbenchHeader
            buildRoute
            compilerOptions
            commandPreview
        }
        .background(AppPalette.window)
    }

    private var workbenchHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BUILD ROUTE · \(model.compileRecipeDraft.name.uppercased())")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                    .lineLimit(1)
                Text("Typed source-to-object contract")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            if let preview = model.compileRecipePreview {
                Label(preview.shortFingerprint, systemImage: "link")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            } else {
                Text("INVALID DRAFT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.danger)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var buildRoute: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SOURCE → COMPILER → TARGET")
                Spacer()
                Text(model.compileRecipePreview == nil ? "CORRECT INVALID FIELDS" : "ALL IDENTIFIERS VALID")
                    .foregroundStyle(model.compileRecipePreview == nil ? AppPalette.danger : AppPalette.success)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(AppPalette.muted)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    routeHeading("SOURCE MEMBER", color: AppPalette.ibmBlue)
                    HStack(spacing: 7) {
                        RecipeTextField(label: "LIBRARY", text: draftBinding(\.sourceLibrary))
                        RecipeTextField(label: "SOURCE FILE", text: draftBinding(\.sourceFile))
                    }
                    RecipeTextField(label: "MEMBER", text: draftBinding(\.sourceMember))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 7) {
                    CompileRecipeSpindleMark(size: 48)
                    Text(model.compileRecipeDraft.toolchain.commandName)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Text("*EVENTF")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.success)
                }
                .frame(width: 86)

                VStack(alignment: .leading, spacing: 7) {
                    routeHeading("PROGRAM OBJECT", color: AppPalette.success)
                    HStack(spacing: 7) {
                        RecipeTextField(label: "LIBRARY", text: draftBinding(\.targetLibrary))
                        RecipeTextField(label: "OBJECT", text: draftBinding(\.targetObject))
                    }
                    HStack {
                        Label("*PGM", systemImage: "shippingbox")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                        Spacer()
                        Toggle("REPLACE", isOn: draftBinding(\.replaceExisting))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .frame(height: 28)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay {
                ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(height: 211)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func routeHeading(_ label: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 3, height: 16)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
        }
    }

    private var compilerOptions: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("COMPILER CONTRACT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Label("Only typed IBM parameters are emitted", systemImage: "checkmark.shield")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.success)
            }
            HStack(spacing: 8) {
                RecipeMenuField(label: "TOOLCHAIN", value: model.compileRecipeDraft.toolchain.label) {
                    ForEach(CompileRecipeToolchain.allCases) { toolchain in
                        Button(toolchain.label) {
                            model.updateCompileRecipeToolchain(toolchain)
                        }
                    }
                }
                RecipeTextField(label: "TARGET RELEASE", text: draftBinding(\.targetRelease))
                RecipeMenuField(label: "DEBUG VIEW", value: model.compileRecipeDraft.debugView.label) {
                    ForEach(CompileRecipeDebugView.allCases) { value in
                        Button(value.label) {
                            model.compileRecipeDraft.debugView = value
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                RecipeMenuField(
                    label: "COMMITMENT",
                    value: model.compileRecipeDraft.sqlCommitment.label,
                    isDisabled: !model.compileRecipeDraft.toolchain.isSQL
                ) {
                    ForEach(CompileRecipeSQLCommitment.allCases) { value in
                        Button(value.label) {
                            model.compileRecipeDraft.sqlCommitment = value
                        }
                    }
                }
                RecipeMenuField(
                    label: "RPG PREPROCESSOR",
                    value: model.compileRecipeDraft.rpgPreprocessor.label,
                    isDisabled: !model.compileRecipeDraft.toolchain.isSQL
                ) {
                    ForEach(CompileRecipeRPGPreprocessor.allCases) { value in
                        Button(value.label) {
                            model.compileRecipeDraft.rpgPreprocessor = value
                        }
                    }
                }
                RecipeMenuField(label: "ENVIRONMENT", value: model.compileRecipeDraft.environment.label) {
                    ForEach(IBMEnvironment.allCases, id: \.rawValue) { environment in
                        Button(environment.label) {
                            model.compileRecipeDraft.environment = environment
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 151)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EXACT COMMAND PREVIEW")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Button {
                    copyCommandPreview()
                } label: {
                    Label("Copy preview", systemImage: "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.compileRecipePreview == nil)
            }
            Text(model.compileRecipePreview?.commandPreview ?? "Correct the highlighted recipe fields to generate a command preview.")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(model.compileRecipePreview == nil ? AppPalette.warning : AppPalette.terminalGreen)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                .background(AppPalette.terminal, in: ChamferedRectangle(cut: 4))
            HStack(spacing: 8) {
                Image(systemName: model.compileRecipePreview == nil ? "exclamationmark.triangle.fill" : "shield.checkered")
                    .foregroundStyle(model.compileRecipePreview == nil ? AppPalette.danger : AppPalette.success)
                Text(model.compileRecipeValidationMessage ?? model.compileRecipeDiagnostic)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppPalette.panel)
    }

    private var evidenceRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                RecipeRouteGlyph(color: AppPalette.ibmBlue, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RUN COMPARISON")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("Recipe drift")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 52)

            VStack(alignment: .leading, spacing: 7) {
                Text("RETAINED RUN")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Picker("Retained run", selection: Binding(
                    get: { model.selectedCompileRunID },
                    set: { id in
                        if let id { model.selectCompileRun(id) }
                    }
                )) {
                    ForEach(model.compileRuns) { run in
                        Text("\(run.displaySequence) · \(run.objectName)").tag(Optional(run.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                if let run = model.selectedCompileRun {
                    Text("\(run.recipe.compiler) · \(run.startedAtLabel)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(2)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("CONTRACT DELTA")
                        Spacer()
                        Text(driftSummary)
                            .foregroundStyle(AppPalette.warning)
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.vertical, 10)

                    ForEach(model.compileRecipeDriftItems) { item in
                        driftRow(item)
                    }

                    executionBoundary
                    storeReceipt
                }
                .padding(.horizontal, 13)
            }
        }
        .background(AppPalette.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppPalette.border).frame(width: 1)
        }
    }

    private var driftSummary: String {
        let exact = model.compileRecipeDriftItems.filter { $0.state == .exact }.count
        let changed = model.compileRecipeDriftItems.filter { $0.state == .changed }.count
        return "\(exact) exact · \(changed) changed"
    }

    private func driftRow(_ item: CompileRecipeDriftItem) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(driftColor(item.state))
                .frame(width: 3, height: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text(item.currentValue)
                    .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                if item.state != .exact {
                    Text("RUN · \(item.retainedValue)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(item.state.label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(driftColor(item.state))
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var executionBoundary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("EXECUTION BOUNDARY", systemImage: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.danger)
            boundaryRow("Remote execution", "NOT CONNECTED", AppPalette.danger)
            boundaryRow("Host writes", "NONE", AppPalette.success)
            boundaryRow("Secrets stored", "NONE", AppPalette.success)
            boundaryRow("Free-form CL", "REFUSED", AppPalette.success)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func boundaryRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var storeReceipt: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LOCAL STORE RECEIPT")
                Spacer()
                Text(model.compileRecipeStatusLabel)
                    .foregroundStyle(model.compileRecipeDraftIsSaved ? AppPalette.terminalGreen : AppPalette.warning)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.terminalGreen)
            Text(model.compileRecipePreview?.fingerprint.uppercased() ?? "NO VALID RECEIPT")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("schema v1 · \(model.compileRecipeLibrary.recipes.count) recipes · permission-restricted file")
                .font(.system(size: 8))
                .foregroundStyle(Color(red: 0.72, green: 0.79, blue: 0.75))
        }
        .padding(11)
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: 4))
        .padding(.bottom, 12)
    }

    private func driftColor(_ state: CompileRecipeDriftState) -> Color {
        switch state {
        case .exact: AppPalette.success
        case .changed: AppPalette.warning
        case .relative: AppPalette.ibmBlue
        case .unavailable: AppPalette.muted
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("PREVIEW ONLY · NO HOST EXECUTION")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("LOCAL STORE · 0600")
                .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .font(.system(size: 8, weight: .regular))
                .italic()
                .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.61))
            Text("ARM64 · NATIVE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<CompileRecipeDraft, Value>) -> Binding<Value> {
        Binding(
            get: { model.compileRecipeDraft[keyPath: keyPath] },
            set: { model.compileRecipeDraft[keyPath: keyPath] = $0 }
        )
    }

    private func copyCommandPreview() {
        guard let command = model.compileRecipePreview?.commandPreview else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        model.compileRecipeDiagnostic = "Copied the deterministic preview to the local clipboard. Nothing was executed."
    }
}

private struct RecipeTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
            TextField(label, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 8)
                .frame(height: 29)
                .background(AppPalette.panel)
                .overlay {
                    ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecipeMenuField<Content: View>: View {
    let label: String
    let value: String
    var isDisabled = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
            Menu {
                content
            } label: {
                HStack {
                    Text(value)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(isDisabled ? AppPalette.muted : AppPalette.text)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
                .background(AppPalette.panel)
                .clipShape(ChamferedRectangle(cut: 3))
                .overlay {
                    ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8)
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(isDisabled)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompileRecipeSpindleMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 38
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            var source = Path()
            source.move(to: point(7, 7))
            source.addLine(to: point(15, 7))
            source.addLine(to: point(15, 18))
            source.addLine(to: point(23, 18))
            source.addLine(to: point(23, 31))
            source.addLine(to: point(31, 31))
            context.stroke(source, with: .color(AppPalette.registrationBlue), lineWidth: 2 * scale)

            var target = Path()
            target.move(to: point(7, 31))
            target.addLine(to: point(13, 31))
            target.addLine(to: point(13, 24))
            target.addLine(to: point(27, 24))
            target.addLine(to: point(27, 7))
            target.addLine(to: point(31, 7))
            context.stroke(target, with: .color(AppPalette.terminalGreen), lineWidth: 2 * scale)

            context.fill(
                Path(CGRect(x: 16 * scale, y: 16 * scale, width: 7 * scale, height: 7 * scale)),
                with: .color(.white)
            )
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: max(3, size * 0.1)))
        .overlay {
            ChamferedRectangle(cut: max(3, size * 0.1))
                .stroke(AppPalette.borderStrong, lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compile recipe spindle")
    }
}

private struct RecipeRouteGlyph: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: 3))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.42, y: 3))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.42, y: canvasSize.height * 0.52))
            path.addLine(to: CGPoint(x: canvasSize.width - 1, y: canvasSize.height * 0.52))
            path.move(to: CGPoint(x: 1, y: canvasSize.height - 2))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.28, y: canvasSize.height - 2))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.28, y: canvasSize.height * 0.72))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.72, y: canvasSize.height * 0.72))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.72, y: 1))
            path.addLine(to: CGPoint(x: canvasSize.width - 1, y: 1))
            context.stroke(path, with: .color(color), lineWidth: 1.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
