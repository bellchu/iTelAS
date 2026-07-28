import XCTest
@testable import iTelASCore

final class CompileRecipeTests: XCTestCase {
    func testRPGRecipeBuildsOneDeterministicTypedCommand() throws {
        let recipe = try makeRecipe()

        XCTAssertEqual(recipe.sourceIdentity, "DEVLIB/QRPGLESRC(ORDERENTRY)")
        XCTAssertEqual(recipe.targetIdentity, "ARLIB/ORDERENTRY · *PGM")
        XCTAssertEqual(recipe.eventFileIdentity, "ARLIB/EVFEVENT(ORDERENTRY)")
        XCTAssertEqual(
            recipe.commandPreview,
            "CRTBNDRPG PGM(ARLIB/ORDERENTRY) SRCFILE(DEVLIB/QRPGLESRC) SRCMBR(ORDERENTRY) OPTION(*EVENTF) DBGVIEW(*SOURCE) TGTRLS(*CURRENT) REPLACE(*YES)"
        )
        XCTAssertEqual(recipe.commandFingerprint.count, 64)
        XCTAssertEqual(recipe.fingerprint, try makeRecipe().fingerprint)

        let release = try CompileTargetReleaseEvidence(commandText: recipe.commandPreview)
        XCTAssertEqual(release.commandToken, .current)
        XCTAssertEqual(release.resolution, .relative)
    }

    func testSQLRPGRecipeDisclosesPrecompileCommitAndEventContracts() throws {
        let recipe = try CompileRecipe(
            id: fixedID,
            name: "Order Entry SQL",
            toolchain: .sqlILERPG,
            sourceLibrary: "ARLIB",
            sourceFile: "QRPGLESRC",
            sourceMember: "ORDERENTRY",
            targetLibrary: "ARLIB",
            targetObject: "ORDERENTRY",
            environment: .qualityAssurance,
            targetRelease: "V7R5M0",
            debugView: .none,
            sqlCommitment: .cursorStability,
            rpgPreprocessor: .levelTwo,
            replaceExisting: false,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(
            recipe.commandPreview,
            "CRTSQLRPGI OBJ(ARLIB/ORDERENTRY) SRCFILE(ARLIB/QRPGLESRC) SRCMBR(ORDERENTRY) OBJTYPE(*PGM) COMMIT(*CS) OPTION(*EVENTF) RPGPPOPT(*LVL2) DBGVIEW(*NONE) TGTRLS(V7R5M0) REPLACE(*NO)"
        )
        XCTAssertEqual(try CompileRecipeTargetRelease("v7r5m0"), .specific(try IBMReleaseLevel("V7R5M0")))
        XCTAssertFalse(recipe.commandPreview.contains("PASSWORD"))
    }

    func testRecipeValidationRefusesInjectionAndInapplicableOptions() throws {
        XCTAssertThrowsError(try makeRecipe(sourceMember: "ORDER) DLTLIB LIB(X")) { error in
            XCTAssertEqual(error as? CompileRecipeError, .invalidIdentifier(field: "Source member"))
        }
        XCTAssertThrowsError(try makeRecipe(targetRelease: "LATEST")) { error in
            XCTAssertEqual(error as? CompileRecipeError, .invalidTargetRelease("LATEST"))
        }
        XCTAssertThrowsError(try makeRecipe(sqlCommitment: .change)) { error in
            XCTAssertEqual(error as? CompileRecipeError, .optionNotApplicable("Commitment control"))
        }
        XCTAssertThrowsError(try makeRecipe(rpgPreprocessor: .levelOne)) { error in
            XCTAssertEqual(error as? CompileRecipeError, .optionNotApplicable("RPG preprocessing"))
        }
    }

    func testRecipeLibraryRoundTripsAndFailsClosedAtIdentityNameAndCountBounds() throws {
        let first = try makeRecipe()
        let second = try makeRecipe(
            id: UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000002")!,
            name: "Order Service",
            sourceMember: "ORDSVC",
            targetObject: "ORDSVC"
        )
        let library = try CompileRecipeLibrary(recipes: [first, second])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(library)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(CompileRecipeLibrary.self, from: data)

        XCTAssertEqual(decoded, library)
        XCTAssertEqual(decoded.fingerprint, library.fingerprint)

        XCTAssertThrowsError(try CompileRecipeLibrary(recipes: [first, first])) { error in
            XCTAssertEqual(error as? CompileRecipeError, .duplicateRecipeID)
        }
        let duplicateName = try makeRecipe(
            id: UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000003")!,
            name: "order entry"
        )
        XCTAssertThrowsError(try CompileRecipeLibrary(recipes: [first, duplicateName])) { error in
            XCTAssertEqual(error as? CompileRecipeError, .duplicateRecipeName("order entry"))
        }
        XCTAssertThrowsError(try CompileRecipeLibrary(
            recipes: [first, second],
            limits: CompileRecipeLimits(maximumRecipes: 1)
        ))
    }

    private let fixedID = UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000001")!
    private let fixedDate = Date(timeIntervalSince1970: 1_774_800_000)

    private func makeRecipe(
        id: UUID? = nil,
        name: String = "Order Entry",
        sourceMember: String = "ORDERENTRY",
        targetObject: String = "ORDERENTRY",
        targetRelease: String = "*CURRENT",
        sqlCommitment: CompileRecipeSQLCommitment = .none,
        rpgPreprocessor: CompileRecipeRPGPreprocessor = .none
    ) throws -> CompileRecipe {
        try CompileRecipe(
            id: id ?? fixedID,
            name: name,
            toolchain: .ileRPG,
            sourceLibrary: "DEVLIB",
            sourceFile: "QRPGLESRC",
            sourceMember: sourceMember,
            targetLibrary: "ARLIB",
            targetObject: targetObject,
            environment: .development,
            targetRelease: targetRelease,
            sqlCommitment: sqlCommitment,
            rpgPreprocessor: rpgPreprocessor,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }
}

private extension CompileRecipeLibrary {
    init(recipes: [CompileRecipe], limits: CompileRecipeLimits) throws {
        try self.init(recipes: recipes)
        try validate(limits: limits)
    }
}
