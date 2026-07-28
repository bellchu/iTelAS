import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class CompileRecipeAppTests: XCTestCase {
    func testPrivateRecipeStoreRoundTripsAndRejectsBroadOrSymlinkCustody() throws {
        let base = temporaryDirectory(named: "store")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = CompileRecipeStore(baseDirectoryURL: base)

        try store.write(CompileRecipeSamples.library)

        XCTAssertEqual(try store.read(), CompileRecipeSamples.library)
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: base.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
        XCTAssertThrowsError(try store.read())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.fileURL.path)

        let linkedBase = temporaryDirectory(named: "leaf-link")
        defer { try? FileManager.default.removeItem(at: linkedBase) }
        try FileManager.default.createDirectory(
            at: linkedBase,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let linkedStore = CompileRecipeStore(baseDirectoryURL: linkedBase)
        try FileManager.default.createSymbolicLink(
            at: linkedStore.fileURL,
            withDestinationURL: store.fileURL
        )
        XCTAssertThrowsError(try linkedStore.read())

        let parentLink = temporaryDirectory(named: "parent-link")
        defer { try? FileManager.default.removeItem(at: parentLink) }
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: base)
        XCTAssertThrowsError(try CompileRecipeStore(baseDirectoryURL: parentLink).read())
    }

    func testModelSavesTypedRecipeAndReloadsItsExactCommand() throws {
        let base = temporaryDirectory(named: "model")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = CompileRecipeStore(baseDirectoryURL: base)
        let model = isolatedModel(recipeStore: store, suffix: "save")

        model.createCompileRecipeDraft()
        model.compileRecipeDraft.name = "Customer inquiry"
        model.updateCompileRecipeToolchain(.sqlILERPG)
        model.compileRecipeDraft.sourceLibrary = "DEVLIB"
        model.compileRecipeDraft.sourceFile = "QRPGLESRC"
        model.compileRecipeDraft.sourceMember = "CUSTINQ"
        model.compileRecipeDraft.targetLibrary = "DEVLIB"
        model.compileRecipeDraft.targetObject = "CUSTINQ"
        model.compileRecipeDraft.rpgPreprocessor = .levelTwo
        model.compileRecipeDraft.sqlCommitment = .cursorStability

        model.saveCompileRecipe()

        XCTAssertFalse(model.compileRecipeUsesBundledDefaults)
        XCTAssertTrue(model.compileRecipeDraftIsSaved)
        let saved = try XCTUnwrap(model.selectedCompileRecipe)
        XCTAssertTrue(saved.commandPreview.hasPrefix("CRTSQLRPGI OBJ(DEVLIB/CUSTINQ)"))
        XCTAssertTrue(saved.commandPreview.contains("OPTION(*EVENTF)"))
        XCTAssertTrue(saved.commandPreview.contains("RPGPPOPT(*LVL2)"))
        XCTAssertEqual(try store.read()?.recipes.first, saved)

        let reloaded = isolatedModel(recipeStore: store, suffix: "reload")
        XCTAssertFalse(reloaded.compileRecipeUsesBundledDefaults)
        XCTAssertEqual(reloaded.selectedCompileRecipe?.commandPreview, saved.commandPreview)
        XCTAssertEqual(reloaded.compileRecipeLibrary.fingerprint, model.compileRecipeLibrary.fingerprint)
    }

    func testRecipeComparisonKeepsRunEvidenceSeparateAndVisible() throws {
        let base = temporaryDirectory(named: "drift")
        defer { try? FileManager.default.removeItem(at: base) }
        let model = isolatedModel(
            recipeStore: CompileRecipeStore(baseDirectoryURL: base),
            suffix: "drift"
        )
        model.presentCompileRecipeStudio()

        XCTAssertTrue(model.isCompileRecipeStudioPresented)
        XCTAssertEqual(model.compileRecipeStatusLabel, "EXAMPLE")
        XCTAssertFalse(model.compileRecipeDraftIsSaved)
        XCTAssertEqual(model.selectedCompileRecipe?.name, "Order Entry")
        XCTAssertEqual(model.selectedCompileRun?.sequence, 184)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "source" })?.state, .exact)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "target" })?.state, .exact)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "toolchain" })?.state, .changed)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "event" })?.state, .exact)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "release" })?.state, .relative)
        XCTAssertEqual(model.compileRecipeDriftItems.first(where: { $0.id == "command" })?.state, .changed)
    }

    func testCompileRecipeStudioRendersAtNativeReviewSize() throws {
        let base = temporaryDirectory(named: "render")
        defer { try? FileManager.default.removeItem(at: base) }
        let model = isolatedModel(
            recipeStore: CompileRecipeStore(baseDirectoryURL: base),
            suffix: "render"
        )
        model.presentCompileRecipeStudio()
        let content = CompileRecipeStudioView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)

        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_COMPILE_RECIPE"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-compile-recipe-native.png"),
                options: .atomic
            )
        }
    }

    private func isolatedModel(recipeStore: CompileRecipeStore, suffix: String) -> AppModel {
        let casebookBase = temporaryDirectory(named: "\(suffix)-casebook")
        let recorderBase = temporaryDirectory(named: "\(suffix)-recorder")
        return AppModel(
            continuityCasebookStore: ContinuityCasebookStore(baseDirectoryURL: casebookBase),
            terminalFlightRecorderStore: TerminalFlightRecorderStore(baseDirectoryURL: recorderBase),
            compileRecipeStore: recipeStore
        )
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-compile-recipe-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }
}
