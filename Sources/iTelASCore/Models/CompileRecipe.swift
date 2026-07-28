import Foundation

public struct CompileRecipeLimits: Equatable, Sendable {
    public let maximumRecipes: Int
    public let maximumNameUTF8Bytes: Int
    public let maximumLibraryUTF8Bytes: Int

    public init(
        maximumRecipes: Int = 64,
        maximumNameUTF8Bytes: Int = 80,
        maximumLibraryUTF8Bytes: Int = 262_144
    ) {
        self.maximumRecipes = min(max(1, maximumRecipes), 256)
        self.maximumNameUTF8Bytes = min(max(8, maximumNameUTF8Bytes), 256)
        self.maximumLibraryUTF8Bytes = min(max(4_096, maximumLibraryUTF8Bytes), 1_048_576)
    }

    public static let standard = CompileRecipeLimits()
}

public enum CompileRecipeError: Error, Equatable, LocalizedError, Sendable {
    case invalidName
    case nameTooLarge(maximum: Int)
    case invalidIdentifier(field: String)
    case invalidTargetRelease(String)
    case optionNotApplicable(String)
    case commandTooLarge(maximum: Int)
    case unsupportedSchema(Int)
    case tooManyRecipes(maximum: Int)
    case duplicateRecipeID
    case duplicateRecipeName(String)
    case libraryTooLarge(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            "Recipe names must contain visible text without control characters."
        case .nameTooLarge(let maximum):
            "Recipe names can contain at most \(maximum) UTF-8 bytes."
        case .invalidIdentifier(let field):
            "\(field) must be a valid IBM i system object name."
        case .invalidTargetRelease(let value):
            "Target release must be *CURRENT, *PRV, or an exact VvRrMm value; received \(value)."
        case .optionNotApplicable(let option):
            "\(option) applies only to the SQL ILE RPG toolchain."
        case .commandTooLarge(let maximum):
            "The generated command exceeds the \(maximum)-byte recipe boundary."
        case .unsupportedSchema(let version):
            "Compile recipe schema \(version) is not supported."
        case .tooManyRecipes(let maximum):
            "A local recipe library can contain at most \(maximum) recipes."
        case .duplicateRecipeID:
            "The recipe library contains a duplicate recipe identity."
        case .duplicateRecipeName(let name):
            "The recipe name is already in use: \(name)."
        case .libraryTooLarge(let maximum):
            "The encoded recipe library exceeds the \(maximum)-byte boundary."
        }
    }
}

public enum CompileRecipeToolchain: String, Codable, CaseIterable, Identifiable, Sendable {
    case ileRPG
    case sqlILERPG

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ileRPG: "ILE RPG program"
        case .sqlILERPG: "SQL ILE RPG program"
        }
    }

    public var languageLabel: String {
        switch self {
        case .ileRPG: "RPGLE"
        case .sqlILERPG: "SQLRPGLE"
        }
    }

    public var commandName: String {
        switch self {
        case .ileRPG: "CRTBNDRPG"
        case .sqlILERPG: "CRTSQLRPGI"
        }
    }

    public var isSQL: Bool { self == .sqlILERPG }
}

public enum CompileRecipeDebugView: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "*NONE"
    case source = "*SOURCE"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum CompileRecipeSQLCommitment: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "*NONE"
    case change = "*CHG"
    case cursorStability = "*CS"
    case all = "*ALL"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum CompileRecipeRPGPreprocessor: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "*NONE"
    case levelOne = "*LVL1"
    case levelTwo = "*LVL2"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum CompileRecipeTargetRelease: Hashable, Codable, Sendable {
    case current
    case previous
    case specific(IBMReleaseLevel)

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "*CURRENT": self = .current
        case "*PRV": self = .previous
        default:
            do {
                self = .specific(try IBMReleaseLevel(normalized))
            } catch {
                throw CompileRecipeError.invalidTargetRelease(rawValue)
            }
        }
    }

    public var commandValue: String {
        switch self {
        case .current: "*CURRENT"
        case .previous: "*PRV"
        case .specific(let release): release.value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(commandValue)
    }
}

public struct CompileRecipe: Identifiable, Hashable, Codable, Sendable {
    public static let maximumCommandUTF8Bytes = 4_096

    public let id: UUID
    public let name: String
    public let toolchain: CompileRecipeToolchain
    public let sourceLibrary: IBMSystemObjectName
    public let sourceFile: IBMSystemObjectName
    public let sourceMember: IBMSystemObjectName
    public let targetLibrary: IBMSystemObjectName
    public let targetObject: IBMSystemObjectName
    public let environment: IBMEnvironment
    public let targetRelease: CompileRecipeTargetRelease
    public let debugView: CompileRecipeDebugView
    public let sqlCommitment: CompileRecipeSQLCommitment
    public let rpgPreprocessor: CompileRecipeRPGPreprocessor
    public let replaceExisting: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        toolchain: CompileRecipeToolchain,
        sourceLibrary: String,
        sourceFile: String,
        sourceMember: String,
        targetLibrary: String,
        targetObject: String,
        environment: IBMEnvironment,
        targetRelease: String,
        debugView: CompileRecipeDebugView = .source,
        sqlCommitment: CompileRecipeSQLCommitment = .none,
        rpgPreprocessor: CompileRecipeRPGPreprocessor = .none,
        replaceExisting: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        limits: CompileRecipeLimits = .standard
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !normalizedName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CompileRecipeError.invalidName
        }
        guard normalizedName.lengthOfBytes(using: .utf8) <= limits.maximumNameUTF8Bytes else {
            throw CompileRecipeError.nameTooLarge(maximum: limits.maximumNameUTF8Bytes)
        }
        guard toolchain.isSQL || sqlCommitment == .none else {
            throw CompileRecipeError.optionNotApplicable("Commitment control")
        }
        guard toolchain.isSQL || rpgPreprocessor == .none else {
            throw CompileRecipeError.optionNotApplicable("RPG preprocessing")
        }

        self.id = id
        self.name = normalizedName
        self.toolchain = toolchain
        self.sourceLibrary = try Self.objectName(sourceLibrary, field: "Source library")
        self.sourceFile = try Self.objectName(sourceFile, field: "Source file")
        self.sourceMember = try Self.objectName(sourceMember, field: "Source member")
        self.targetLibrary = try Self.objectName(targetLibrary, field: "Target library")
        self.targetObject = try Self.objectName(targetObject, field: "Target object")
        self.environment = environment
        self.targetRelease = try CompileRecipeTargetRelease(targetRelease)
        self.debugView = debugView
        self.sqlCommitment = sqlCommitment
        self.rpgPreprocessor = rpgPreprocessor
        self.replaceExisting = replaceExisting
        self.createdAt = Self.persistenceDate(createdAt)
        self.updatedAt = Self.persistenceDate(updatedAt)

        guard commandPreview.lengthOfBytes(using: .utf8) <= Self.maximumCommandUTF8Bytes else {
            throw CompileRecipeError.commandTooLarge(maximum: Self.maximumCommandUTF8Bytes)
        }
    }

    public var sourceIdentity: String {
        "\(sourceLibrary.value)/\(sourceFile.value)(\(sourceMember.value))"
    }

    public var targetIdentity: String {
        "\(targetLibrary.value)/\(targetObject.value) · *PGM"
    }

    public var eventFileIdentity: String {
        "\(targetLibrary.value)/EVFEVENT(\(targetObject.value))"
    }

    public var commandPreview: String {
        var tokens = [toolchain.commandName]
        switch toolchain {
        case .ileRPG:
            tokens.append("PGM(\(targetLibrary.value)/\(targetObject.value))")
        case .sqlILERPG:
            tokens.append("OBJ(\(targetLibrary.value)/\(targetObject.value))")
        }
        tokens.append("SRCFILE(\(sourceLibrary.value)/\(sourceFile.value))")
        tokens.append("SRCMBR(\(sourceMember.value))")
        if toolchain.isSQL {
            tokens.append("OBJTYPE(*PGM)")
            tokens.append("COMMIT(\(sqlCommitment.rawValue))")
        }
        tokens.append("OPTION(*EVENTF)")
        if toolchain.isSQL {
            tokens.append("RPGPPOPT(\(rpgPreprocessor.rawValue))")
        }
        tokens.append("DBGVIEW(\(debugView.rawValue))")
        tokens.append("TGTRLS(\(targetRelease.commandValue))")
        tokens.append("REPLACE(\(replaceExisting ? "*YES" : "*NO"))")
        return tokens.joined(separator: " ")
    }

    public var commandFingerprint: String {
        AIContentFingerprint.sha256(commandPreview)
    }

    public var fingerprint: String {
        let fields = [
            "itelas-compile-recipe-v1",
            id.uuidString.lowercased(),
            name,
            environment.rawValue,
            sourceIdentity,
            targetIdentity,
            commandPreview
        ]
        return AIContentFingerprint.sha256(
            fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        )
    }

    public var shortFingerprint: String {
        String(fingerprint.prefix(10)).uppercased()
    }

    public func validate(limits: CompileRecipeLimits = .standard) throws {
        _ = try CompileRecipe(
            id: id,
            name: name,
            toolchain: toolchain,
            sourceLibrary: sourceLibrary.value,
            sourceFile: sourceFile.value,
            sourceMember: sourceMember.value,
            targetLibrary: targetLibrary.value,
            targetObject: targetObject.value,
            environment: environment,
            targetRelease: targetRelease.commandValue,
            debugView: debugView,
            sqlCommitment: sqlCommitment,
            rpgPreprocessor: rpgPreprocessor,
            replaceExisting: replaceExisting,
            createdAt: createdAt,
            updatedAt: updatedAt,
            limits: limits
        )
    }

    private static func objectName(_ value: String, field: String) throws -> IBMSystemObjectName {
        do {
            return try IBMSystemObjectName(value.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw CompileRecipeError.invalidIdentifier(field: field)
        }
    }

    private static func persistenceDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
    }
}

public struct CompileRecipeLibrary: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public private(set) var recipes: [CompileRecipe]

    public init(recipes: [CompileRecipe] = []) throws {
        schemaVersion = Self.currentSchemaVersion
        self.recipes = recipes
        try validate()
    }

    public mutating func upsert(
        _ recipe: CompileRecipe,
        limits: CompileRecipeLimits = .standard
    ) throws {
        try recipe.validate(limits: limits)
        if let duplicate = recipes.first(where: {
            $0.id != recipe.id && $0.name.compare(recipe.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            throw CompileRecipeError.duplicateRecipeName(duplicate.name)
        }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            guard recipes.count < limits.maximumRecipes else {
                throw CompileRecipeError.tooManyRecipes(maximum: limits.maximumRecipes)
            }
            recipes.insert(recipe, at: 0)
        }
        try validate(limits: limits)
    }

    public mutating func remove(id: UUID, limits: CompileRecipeLimits = .standard) throws {
        recipes.removeAll { $0.id == id }
        try validate(limits: limits)
    }

    public func validate(limits: CompileRecipeLimits = .standard) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CompileRecipeError.unsupportedSchema(schemaVersion)
        }
        guard recipes.count <= limits.maximumRecipes else {
            throw CompileRecipeError.tooManyRecipes(maximum: limits.maximumRecipes)
        }
        guard Set(recipes.map(\.id)).count == recipes.count else {
            throw CompileRecipeError.duplicateRecipeID
        }
        var names: Set<String> = []
        for recipe in recipes {
            try recipe.validate(limits: limits)
            let folded = recipe.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(folded).inserted else {
                throw CompileRecipeError.duplicateRecipeName(recipe.name)
            }
        }
    }

    public var fingerprint: String {
        let fields = ["itelas-compile-recipe-library-v1"] + recipes.map(\.fingerprint)
        return AIContentFingerprint.sha256(
            fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        )
    }

    public var shortFingerprint: String {
        String(fingerprint.prefix(10)).uppercased()
    }
}
