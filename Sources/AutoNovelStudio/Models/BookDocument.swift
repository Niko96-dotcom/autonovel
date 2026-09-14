import Foundation

enum DocumentRole: String, Hashable {
    case required = "You provide"
    case generated = "AI generated, editable"
    case guardrail = "Advanced"
    case chapter = "Draft"
}

struct BookDocument: Identifiable, Hashable {
    let fileName: String
    let title: String
    let summary: String
    let symbol: String
    let role: DocumentRole
    let guidance: [String]

    var id: String { fileName }

    static let seed = BookDocument(
        fileName: "seed.txt",
        title: "Story Seed",
        summary: "The compact brief every other part of the book grows from.",
        symbol: "sparkles",
        role: .required,
        guidance: [
            "Describe the protagonist, what they want, and what stands in the way.",
            "Name the unusual world or speculative hook and its cost.",
            "State the emotional promise, stakes, and any hard boundaries.",
            "You can create this automatically from New Book Setup.",
        ]
    )

    static let world = BookDocument(
        fileName: "world.md",
        title: "World",
        summary: "Places, history, culture, rules, magic, costs, and limitations.",
        symbol: "globe.europe.africa",
        role: .generated,
        guidance: [
            "The pipeline can generate this from your Story Seed.",
            "Edit anything that feels generic or contradicts your idea.",
            "Concrete rules and costs matter more than encyclopedic lore.",
        ]
    )

    static let characters = BookDocument(
        fileName: "characters.md",
        title: "Characters",
        summary: "Who acts, what they want, how they change, and how they sound.",
        symbol: "person.3",
        role: .generated,
        guidance: [
            "Each major character needs a want, need, wound, lie, and secret.",
            "Dialogue patterns should remain distinct without speaker tags.",
            "Change names, relationships, or motives directly here.",
        ]
    )

    static let voice = BookDocument(
        fileName: "voice.md",
        title: "Voice & Style",
        summary: "How the prose should feel: POV, tense, rhythm, vocabulary, and limits.",
        symbol: "waveform",
        role: .generated,
        guidance: [
            "Keep Part 1 as general craft guardrails.",
            "Use Part 2 for this book’s specific voice and examples.",
            "Add a short sample that sounds right and one that sounds wrong.",
        ]
    )

    static let outline = BookDocument(
        fileName: "outline.md",
        title: "Outline",
        summary: "Chapter beats, emotional movement, escalation, plants, and payoffs.",
        symbol: "point.3.connected.trianglepath.dotted",
        role: .generated,
        guidance: [
            "The pipeline generates this after World and Characters.",
            "Every chapter needs a change, not merely an event.",
            "Check that promises planted early receive later payoffs.",
        ]
    )

    static let canon = BookDocument(
        fileName: "canon.md",
        title: "Canon",
        summary: "The checkable facts the book must never contradict.",
        symbol: "checkmark.seal",
        role: .generated,
        guidance: [
            "Use one short, testable fact per bullet.",
            "Record ages, dates, physical traits, geography, and system rules.",
            "Update this when a drafted chapter establishes something new.",
        ]
    )

    static let mystery = BookDocument(
        fileName: "MYSTERY.md",
        title: "Secrets",
        summary: "Author-only truths, reveals, hidden motives, and ending knowledge.",
        symbol: "key",
        role: .generated,
        guidance: [
            "The foundation phase can propose this from your Story Seed.",
            "Write the truth even if the reader will not learn it until late.",
            "Separate deliberate mystery from facts the author has not decided.",
            "Track who knows each secret and when the reader learns it.",
        ]
    )

    static let primary: [BookDocument] = [
        .seed, .world, .characters, .voice, .outline, .canon, .mystery,
    ]

    static let advanced: [BookDocument] = [
        BookDocument(
            fileName: "program.md",
            title: "Pipeline Instructions",
            summary: "The operating rules for the autonomous writing loop.",
            symbol: "gearshape.2",
            role: .guardrail,
            guidance: ["Change this only when you want to alter how the whole pipeline behaves."]
        ),
        BookDocument(
            fileName: "CRAFT.md",
            title: "Craft Framework",
            summary: "The craft principles the writer and judge use.",
            symbol: "hammer",
            role: .guardrail,
            guidance: ["This is reusable across books; ordinary book setup does not require editing it."]
        ),
        BookDocument(
            fileName: "ANTI-SLOP.md",
            title: "Anti-Slop Rules",
            summary: "Word-level patterns the evaluator penalizes.",
            symbol: "text.badge.xmark",
            role: .guardrail,
            guidance: ["Tune this only if the checker is rewarding or punishing the wrong prose habits."]
        ),
        BookDocument(
            fileName: "ANTI-PATTERNS.md",
            title: "Structural Anti-Patterns",
            summary: "Scene and chapter shapes the pipeline should avoid.",
            symbol: "exclamationmark.triangle",
            role: .guardrail,
            guidance: ["These rules are reusable and optional to edit."]
        ),
    ]

    static func forSection(_ section: StudioSection) -> BookDocument? {
        switch section {
        case .seed: .seed
        case .world: .world
        case .characters: .characters
        case .voice: .voice
        case .outline: .outline
        case .canon: .canon
        case .mystery: .mystery
        default: nil
        }
    }
}
