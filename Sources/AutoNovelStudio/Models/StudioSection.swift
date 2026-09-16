import Foundation

enum StudioSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case setup
    case seed
    case world
    case characters
    case voice
    case outline
    case canon
    case mystery
    case chapters
    case rules
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .setup: "New Book Setup"
        case .seed: "Story Seed"
        case .world: "World"
        case .characters: "Characters"
        case .voice: "Voice & Style"
        case .outline: "Outline"
        case .canon: "Canon"
        case .mystery: "Secrets"
        case .chapters: "Chapters"
        case .rules: "Writing Rules"
        case .activity: "Activity & Logs"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .setup: "wand.and.stars"
        case .seed: "sparkles"
        case .world: "globe.europe.africa"
        case .characters: "person.3"
        case .voice: "waveform"
        case .outline: "point.3.connected.trianglepath.dotted"
        case .canon: "checkmark.seal"
        case .mystery: "key"
        case .chapters: "books.vertical"
        case .rules: "slider.horizontal.3"
        case .activity: "terminal"
        }
    }

    static let startHere: [StudioSection] = [.overview, .setup]
    static let bookFiles: [StudioSection] = [
        .seed, .world, .characters, .voice, .outline, .canon, .mystery, .chapters,
    ]
    static let advanced: [StudioSection] = [.rules, .activity]
}
