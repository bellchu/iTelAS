import Foundation

struct WorkbenchProverb: Identifiable, Hashable {
    let id: String
    let text: String
    let source: String
    let lesson: String

    static let library: [WorkbenchProverb] = [
        .init(id: "measure-twice", text: "Measure twice, cut once.", source: "English proverb", lesson: "Production safety"),
        .init(id: "verify", text: "Trust, but verify.", source: "Russian proverb", lesson: "Operations"),
        .init(id: "prevention", text: "An ounce of prevention is worth a pound of cure.", source: "Benjamin Franklin", lesson: "System health"),
        .init(id: "planning", text: "Plans are nothing; planning is everything.", source: "Dwight D. Eisenhower", lesson: "Runbooks"),
        .init(id: "ink", text: "The palest ink is better than the best memory.", source: "Chinese proverb", lesson: "Job logs"),
        .init(id: "steady", text: "Slow is smooth; smooth is fast.", source: "Operational maxim", lesson: "Change control"),
        .init(id: "beginning", text: "The beginning is the most important part of the work.", source: "Plato", lesson: "Architecture"),
        .init(id: "resilience", text: "Fall seven times, stand up eight.", source: "Japanese proverb", lesson: "Incident response"),
        .init(id: "action", text: "Well done is better than well said.", source: "Benjamin Franklin", lesson: "Delivery"),
        .init(id: "experience", text: "Experience is the name everyone gives to their mistakes.", source: "Oscar Wilde", lesson: "Modernization")
    ]

    static func random(excluding current: String? = nil) -> WorkbenchProverb {
        let candidates = library.filter { $0.id != current }
        return candidates.randomElement() ?? library[0]
    }
}
