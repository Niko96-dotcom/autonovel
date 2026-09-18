import Foundation

struct BookBrief: Codable, Equatable {
    var title = ""
    var author = ""
    var genre = "Fantasy"
    var audience = "Adult"
    var pointOfView = "Third person limited"
    var tense = "Past tense"
    var targetWords = 80_000
    var targetChapters = 24
    var premise = ""
    var protagonist = ""
    var protagonistWant = ""
    var centralConflict = ""
    var stakes = ""
    var worldHook = ""
    var speculativeElement = ""
    var costsAndLimits = ""
    var themes = ""
    var toneAndPromise = ""
    var endingDirection = ""
    var mustInclude = ""
    var avoid = ""
    var contentNotes = ""

    enum CodingKeys: String, CodingKey {
        case title, author, genre, audience, pointOfView, tense
        case targetWords, targetChapters, premise, protagonist, protagonistWant
        case centralConflict, stakes, worldHook, speculativeElement, costsAndLimits
        case themes, toneAndPromise, endingDirection, mustInclude, avoid, contentNotes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try box.decodeIfPresent(String.self, forKey: .author) ?? ""
        genre = try box.decodeIfPresent(String.self, forKey: .genre) ?? "Fantasy"
        audience = try box.decodeIfPresent(String.self, forKey: .audience) ?? "Adult"
        pointOfView = try box.decodeIfPresent(String.self, forKey: .pointOfView) ?? "Third person limited"
        tense = try box.decodeIfPresent(String.self, forKey: .tense) ?? "Past tense"
        targetWords = try box.decodeIfPresent(Int.self, forKey: .targetWords) ?? 80_000
        targetChapters = try box.decodeIfPresent(Int.self, forKey: .targetChapters) ?? 24
        premise = try box.decodeIfPresent(String.self, forKey: .premise) ?? ""
        protagonist = try box.decodeIfPresent(String.self, forKey: .protagonist) ?? ""
        protagonistWant = try box.decodeIfPresent(String.self, forKey: .protagonistWant) ?? ""
        centralConflict = try box.decodeIfPresent(String.self, forKey: .centralConflict) ?? ""
        stakes = try box.decodeIfPresent(String.self, forKey: .stakes) ?? ""
        worldHook = try box.decodeIfPresent(String.self, forKey: .worldHook) ?? ""
        speculativeElement = try box.decodeIfPresent(String.self, forKey: .speculativeElement) ?? ""
        costsAndLimits = try box.decodeIfPresent(String.self, forKey: .costsAndLimits) ?? ""
        themes = try box.decodeIfPresent(String.self, forKey: .themes) ?? ""
        toneAndPromise = try box.decodeIfPresent(String.self, forKey: .toneAndPromise) ?? ""
        endingDirection = try box.decodeIfPresent(String.self, forKey: .endingDirection) ?? ""
        mustInclude = try box.decodeIfPresent(String.self, forKey: .mustInclude) ?? ""
        avoid = try box.decodeIfPresent(String.self, forKey: .avoid) ?? ""
        contentNotes = try box.decodeIfPresent(String.self, forKey: .contentNotes) ?? ""
    }

    var requiredCompleted: Int {
        [title, premise, protagonist, centralConflict, worldHook]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    mutating func clampTargets() {
        targetWords = min(200_000, max(15_000, targetWords))
        targetChapters = min(80, max(5, targetChapters))
    }

    var seedText: String {
        """
        # \(title.isEmpty ? "Untitled Novel" : title)

        ## Book shape
        - Author: \(author.isEmpty ? "Not specified" : author)
        - Genre / subgenre: \(genre)
        - Intended audience: \(audience)
        - Point of view: \(pointOfView)
        - Tense: \(tense)
        - Target length: \(targetWords) words across approximately \(targetChapters) chapters

        ## Premise
        \(value(premise))

        ## Protagonist
        \(value(protagonist))

        ## What the protagonist wants
        \(value(protagonistWant))

        ## Central conflict
        \(value(centralConflict))

        ## Stakes
        \(value(stakes))

        ## World hook
        \(value(worldHook))

        ## Speculative element or magic
        \(value(speculativeElement))

        ## Costs and limitations
        \(value(costsAndLimits))

        ## Themes to explore
        \(value(themes))

        ## Tone and reader promise
        \(value(toneAndPromise))

        ## Ending direction
        \(value(endingDirection))

        ## Must include
        \(value(mustInclude))

        ## Avoid and hard boundaries
        \(value(avoid))

        ## Content and intensity notes
        \(value(contentNotes))
        """
    }

    private func value(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Not specified — let the pipeline propose options."
            : text
    }
}
