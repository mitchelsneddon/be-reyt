import Foundation

public enum ReflectionValidation: Equatable, Sendable {
    case valid(WeeklyReflectionContent)
    case invalid([String])
}

/// Checks a model-written candidate against exactly what the model was shown. The model is never trusted with
/// dates or numbers: every cited day must be a day with content in this week, and every digit sequence in the
/// prose must appear in the journal itself (so "your 5k" passes when "5k" was written, "4 days" does not).
public enum ReflectionValidator {
    public static let maxOverviewLength = 900
    public static let maxPointLength = 320
    public static let maxThemeTitleLength = 80
    public static let maxThemeSummaryLength = 320
    public static let maxQuestionLength = 220
    public static let maxQuestions = 2
    public static let maxItemsPerSection = 4

    public static func validate(_ candidate: WeeklyReflectionContent, against input: ReflectionInput)
        -> ReflectionValidation
    {
        var reasons: [String] = []
        let allowedDays = Set(input.days.map(\.dateKey))
        let weekDays = Set((0..<7).map { input.weekStart.adding(days: $0) })
        let sourceNumbers = numbers(in: sourceText(input))

        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func checkDates(_ keys: [DateKey], _ what: String) {
            for key in Set(keys) {
                if !weekDays.contains(key) {
                    reasons.append("\(what) cites \(key.string), which is outside this week")
                } else if !allowedDays.contains(key) {
                    reasons.append("\(what) cites \(key.string), which has no entry")
                }
            }
        }
        func checkText(_ text: String, max: Int, _ what: String) {
            if text.count > max { reasons.append("\(what) is too long (keep it under \(max) characters)") }
            for n in numbers(in: text).subtracting(sourceNumbers).sorted() {
                reasons.append(
                    "\(what) mentions the number \(n), which the person did not write; do not state any numbers")
            }
        }

        var out = WeeklyReflectionContent(
            overview: trimmed(candidate.overview), highlights: [], difficult: [], themes: [], questions: [])
        if out.overview.isEmpty { reasons.append("the overview is empty") }
        checkText(out.overview, max: maxOverviewLength, "the overview")

        func points(_ source: [WeeklyReflectionContent.Point], _ label: String)
            -> [WeeklyReflectionContent.Point]
        {
            if source.count > maxItemsPerSection { reasons.append("too many \(label) (at most \(maxItemsPerSection))") }
            var result: [WeeklyReflectionContent.Point] = []
            for (i, p) in source.enumerated() {
                let text = trimmed(p.text)
                if text.isEmpty {
                    reasons.append("\(label) item \(i + 1) is empty")
                    continue
                }
                checkText(text, max: maxPointLength, "\(label) item \(i + 1)")
                checkDates(p.dateKeys, "\(label) item \(i + 1)")
                result.append(.init(text: text, dateKeys: Array(Set(p.dateKeys)).sorted()))
            }
            return result
        }
        out.highlights = points(candidate.highlights, "highlights")
        out.difficult = points(candidate.difficult, "difficult moments")

        if candidate.themes.count > maxItemsPerSection {
            reasons.append("too many themes (at most \(maxItemsPerSection))")
        }
        for (i, t) in candidate.themes.enumerated() {
            let title = trimmed(t.title)
            let summary = trimmed(t.summary)
            let what = "theme \(i + 1)"
            if title.isEmpty || summary.isEmpty {
                reasons.append("\(what) needs a title and a summary")
                continue
            }
            if t.dateKeys.isEmpty { reasons.append("\(what) needs at least one supporting date") }
            checkText(title, max: maxThemeTitleLength, "\(what) title")
            checkText(summary, max: maxThemeSummaryLength, "\(what) summary")
            checkDates(t.dateKeys, what)
            out.themes.append(.init(title: title, summary: summary, dateKeys: Array(Set(t.dateKeys)).sorted()))
        }

        if candidate.questions.count > maxQuestions {
            reasons.append("too many questions (at most \(maxQuestions))")
        }
        for (i, q) in candidate.questions.enumerated() {
            let text = trimmed(q)
            if text.isEmpty { continue }
            checkText(text, max: maxQuestionLength, "question \(i + 1)")
            out.questions.append(text)
        }

        return reasons.isEmpty ? .valid(out) : .invalid(reasons)
    }

    /// Everything the person wrote that the model was shown, joined for number matching.
    static func sourceText(_ input: ReflectionInput) -> String {
        var parts: [String] = []
        for d in input.days {
            parts.append(d.text)
            parts.append(contentsOf: [d.smileAnswer, d.rotatingPrompt, d.rotatingAnswer].compactMap { $0 })
            parts.append(contentsOf: d.tagNames)
        }
        if let i = input.intention {
            parts.append(i.text)
            if let c = i.category { parts.append(c) }
        }
        parts.append(contentsOf: input.followUps.map(\.note))
        parts.append(contentsOf: input.workouts.map(\.activity))
        return parts.joined(separator: "\n")
    }

    /// Maximal runs of digits ("5k" gives "5", "10k" gives "10").
    static func numbers(in text: String) -> Set<String> {
        var runs = Set<String>()
        var current = ""
        for ch in text {
            if ch.wholeNumberValue != nil {
                current.append(ch)
            } else if !current.isEmpty {
                runs.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.insert(current) }
        return runs
    }
}
