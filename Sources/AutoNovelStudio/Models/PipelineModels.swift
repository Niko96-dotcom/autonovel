import Foundation

struct PipelineState: Codable, Equatable {
    var phase = "foundation"
    var status = ""
    var currentFocus: String?
    var iteration = 0
    var foundationScore = 0.0
    var loreScore = 0.0
    var chaptersDrafted = 0
    var chaptersTotal = 0
    var novelScore: Double?
    var revisionCycle = 0
    var debts: [PipelineDebt] = []
    var lastError: PipelineErrorDetails?

    enum CodingKeys: String, CodingKey {
        case phase
        case status
        case currentFocus = "current_focus"
        case iteration
        case foundationScore = "foundation_score"
        case loreScore = "lore_score"
        case chaptersDrafted = "chapters_drafted"
        case chaptersTotal = "chapters_total"
        case novelScore = "novel_score"
        case revisionCycle = "revision_cycle"
        case debts
        case lastError = "last_error"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        phase = try box.decodeIfPresent(String.self, forKey: .phase) ?? "foundation"
        status = try box.decodeIfPresent(String.self, forKey: .status) ?? ""
        currentFocus = try box.decodeIfPresent(String.self, forKey: .currentFocus)
        iteration = try box.decodeIfPresent(Int.self, forKey: .iteration) ?? 0
        foundationScore = try box.decodeIfPresent(Double.self, forKey: .foundationScore) ?? 0
        loreScore = try box.decodeIfPresent(Double.self, forKey: .loreScore) ?? 0
        chaptersDrafted = try box.decodeIfPresent(Int.self, forKey: .chaptersDrafted) ?? 0
        chaptersTotal = try box.decodeIfPresent(Int.self, forKey: .chaptersTotal) ?? 0
        novelScore = try box.decodeIfPresent(Double.self, forKey: .novelScore)
        revisionCycle = try box.decodeIfPresent(Int.self, forKey: .revisionCycle) ?? 0
        debts = try box.decodeIfPresent([PipelineDebt].self, forKey: .debts) ?? []
        lastError = try box.decodeIfPresent(PipelineErrorDetails.self, forKey: .lastError)
    }
}

struct PipelineErrorDetails: Codable, Equatable {
    var phase = ""
    var step = ""
    var message = ""
    var occurredAt = ""
    var logPath: String?

    enum CodingKeys: String, CodingKey {
        case phase, step, message
        case occurredAt = "occurred_at"
        case logPath = "log_path"
    }
}

struct PipelineDebt: Codable, Equatable, Identifiable {
    var trigger = ""
    var affected: [String] = []
    var status = "pending"
    var id: String { trigger + affected.joined() }
}

struct ChapterInfo: Identifiable, Hashable {
    let number: Int
    let url: URL
    let title: String
    let excerpt: String
    let words: Int
    var id: Int { number }

    var numberLabel: String { number.formatted(.number.precision(.integerLength(2))) }

    static func parse(number: Int, url: URL, text: String) -> ChapterInfo {
        let lines = text.components(separatedBy: .newlines)
        let heading = lines.first { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("# ") && trimmed.dropFirst(2).contains(where: { !$0.isWhitespace })
        }
        let parsedTitle = heading.map {
            String($0.trimmingCharacters(in: .whitespaces).dropFirst(2))
                .trimmingCharacters(in: .whitespaces)
        }
        let title = parsedTitle?.isEmpty == false ? parsedTitle! : "Chapter \(numberLabel(for: number))"
        let excerptLine = lines.first { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        } ?? ""
        let excerpt = excerptLine
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        return ChapterInfo(number: number, url: url, title: title, excerpt: excerpt, words: words)
    }

    private static func numberLabel(for number: Int) -> String {
        number.formatted(.number.precision(.integerLength(2)))
    }
}

struct ActivityRecord: Identifiable, Hashable {
    let index: Int
    let columns: [String]
    var id: Int { index }

    var title: String { columns.dropFirst().first ?? columns.first ?? "Activity" }
    var detail: String { columns.suffix(2).joined(separator: " · ") }
    var score: Double? {
        guard columns.indices.contains(2) else { return nil }
        return Double(columns[2])
    }
    var resultStatus: String {
        columns.indices.contains(4) ? columns[4].lowercased() : ""
    }
    var isFailure: Bool {
        (score ?? 0) < 0 || ["failed", "error"].contains(resultStatus)
    }
    var isDiscarded: Bool { resultStatus == "discard" }
    var isForced: Bool {
        resultStatus == "forced" || (columns.indices.contains(2) && score == nil)
    }
    /// Forced keeps are not successes — Dashboard must not paint them moss green.
    var isSuccessAppearance: Bool {
        !isFailure && !isDiscarded && !isForced
    }
    var resultSymbol: String {
        if isFailure { return "exclamationmark.triangle.fill" }
        if isDiscarded { return "arrow.counterclockwise.circle" }
        if isForced { return "exclamationmark.triangle.fill" }
        return "checkmark.circle"
    }
}

enum PipelinePhase: String, CaseIterable, Identifiable {
    case foundation, drafting, revision, export, complete
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .foundation: "building.columns"
        case .drafting: "pencil.and.outline"
        case .revision: "arrow.triangle.2.circlepath"
        case .export: "shippingbox"
        case .complete: "checkmark.circle.fill"
        }
    }
}
