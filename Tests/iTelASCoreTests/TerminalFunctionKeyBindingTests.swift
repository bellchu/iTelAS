import XCTest
@testable import iTelASCore

final class TerminalFunctionKeyBindingTests: XCTestCase {
    func testStandardLayoutMapsEveryPhysicalSlotAndPreservesIBMDefaults() {
        let bindings = TerminalFunctionKeyBinding.standard

        XCTAssertEqual(bindings.count, 24)
        XCTAssertEqual(bindings.map(\.slot), Array(1...24))
        XCTAssertEqual(bindings.map(\.hostFunction), Array(1...24))
        XCTAssertTrue(bindings.allSatisfy(\.isIdentityRoute))
        XCTAssertEqual(bindings.filter(\.isPinned).map(\.slot), [1, 3, 4, 5, 9, 12])
        XCTAssertEqual(bindings.first(where: { $0.slot == 1 })?.displayLabel, "Help")
        XCTAssertEqual(bindings.first(where: { $0.slot == 3 })?.displayLabel, "Exit")
        XCTAssertEqual(bindings.first(where: { $0.slot == 4 })?.displayLabel, "Prompt")
        XCTAssertEqual(bindings.first(where: { $0.slot == 5 })?.displayLabel, "Refresh")
        XCTAssertEqual(bindings.first(where: { $0.slot == 9 })?.displayLabel, "Retrieve")
        XCTAssertEqual(bindings.first(where: { $0.slot == 12 })?.displayLabel, "Cancel")
        XCTAssertEqual(bindings.first(where: { $0.slot == 13 })?.physicalKeyLabel, "⇧F1")
        XCTAssertEqual(bindings.first(where: { $0.slot == 24 })?.hostActionLabel, "F24")
        XCTAssertTrue(TerminalFunctionKeyBinding.validationErrors(for: bindings).isEmpty)
    }

    func testValidationRejectsIncompleteDuplicateInvalidAndUnsafeBindings() {
        var bindings = TerminalFunctionKeyBinding.standard
        bindings[1].slot = 1
        bindings[2].hostFunction = 25
        bindings[3].label = String(repeating: "x", count: TerminalFunctionKeyBinding.maximumLabelLength + 1)
        bindings[4].label = "\nRefresh"

        let errors = TerminalFunctionKeyBinding.validationErrors(for: bindings)

        XCTAssertTrue(errors.contains("Function-key layout must contain each F1–F24 slot exactly once."))
        XCTAssertTrue(errors.contains("F3 must route to a host function from F1 through F24."))
        XCTAssertTrue(errors.contains("F4 label must be at most 32 characters."))
        XCTAssertTrue(errors.contains("F5 label cannot contain control characters."))
    }

    func testLegacyProfileDefaultsFunctionKeyBindingsToStandardLayout() throws {
        let legacyJSON = Data(#"{"name":"Legacy","host":"legacy.example.com","ccsid":37}"#.utf8)

        let profile = try JSONDecoder().decode(SessionProfile.self, from: legacyJSON)

        XCTAssertEqual(profile.functionKeyBindings, TerminalFunctionKeyBinding.standard)
        XCTAssertTrue(profile.validationErrors.isEmpty)
    }

    func testCustomizedFunctionKeyBindingsRoundTripThroughProfileJSON() throws {
        var bindings = TerminalFunctionKeyBinding.standard
        bindings[0] = TerminalFunctionKeyBinding(
            slot: 1,
            hostFunction: 12,
            label: "Abort request",
            isPinned: false
        )
        bindings[11] = TerminalFunctionKeyBinding(
            slot: 12,
            hostFunction: 1,
            label: "Context help",
            isPinned: true
        )
        let profile = SessionProfile(
            id: UUID(uuidString: "6D0A81AA-7D06-48F2-9C3B-E924FA36C4AF")!,
            name: "Architect",
            host: "ibmi.example.com",
            functionKeyBindings: bindings
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(SessionProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.functionKeyBindings[0].hostFunction, 12)
        XCTAssertEqual(decoded.functionKeyBindings[0].displayLabel, "Abort request")
        XCTAssertFalse(decoded.functionKeyBindings[0].isPinned)
        XCTAssertEqual(decoded.functionKeyBindings[11].hostFunction, 1)
        XCTAssertEqual(decoded.functionKeyBindings[11].displayLabel, "Context help")
        XCTAssertTrue(decoded.functionKeyBindings[11].isPinned)
    }
}
