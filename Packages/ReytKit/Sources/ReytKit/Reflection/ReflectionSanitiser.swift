import Foundation

/// Tidies a model-written candidate before it is validated. Everything here is a quiet repair or a quiet drop:
/// a weak theme, an uncited point or a missing question mark never costs the whole reflection. Only an empty
/// overview (checked later by the validator) and the numeral rule remain fatal.
public enum ReflectionSanitiser {
    /// Two highlights citing the same single day are duplicates when at least this share of their words overlap.
    static let duplicateOverlap = 0.6

    public static func sanitise(_ candidate: WeeklyReflectionContent, against input: ReflectionInput)
        -> WeeklyReflectionContent
    {
        let weekDays = Set((0..<7).map { input.weekStart.adding(days: $0) })
        let valid = Set(input.days.map(\.dateKey)).intersection(weekDays)

        func clean(_ keys: [DateKey]) -> [DateKey] { Array(Set(keys).intersection(valid)).sorted() }
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

        func points(_ source: [WeeklyReflectionContent.Point]) -> [WeeklyReflectionContent.Point] {
            source.compactMap { p in
                let keys = clean(p.dateKeys)
                let text = trimmed(p.text)
                return keys.isEmpty || text.isEmpty ? nil : .init(text: text, dateKeys: keys)
            }
        }

        let evidence = Evidence(input)
        var out = candidate
        out.overview = filterSentences(trimmed(candidate.overview)) { evidence.weekAllows($0) }
        out.highlights = dedupe(
            grounded(points(candidate.highlights), evidence, needsDifficultySignal: false))
        out.difficult = dedupe(grounded(points(candidate.difficult), evidence, needsDifficultySignal: true))
        out.themes = candidate.themes.compactMap { t in
            let keys = clean(t.dateKeys)
            let title = filterSentences(trimmed(t.title)) { evidence.allows($0, on: keys) }
            let summary = filterSentences(trimmed(t.summary)) { evidence.allows($0, on: keys) }
            guard keys.count >= 2, !title.isEmpty, !summary.isEmpty else { return nil }
            let supported = keys.filter { evidence.overlap(title + " " + summary, on: $0) >= 1 }
            return supported.isEmpty ? nil : .init(title: title, summary: summary, dateKeys: keys)
        }
        out.questions = candidate.questions.compactMap { q in
            let text = filterSentences(trimmed(q)) { evidence.weekAllows($0) }
            if text.isEmpty { return nil }
            return text.hasSuffix("?") ? text : text + "?"
        }
        return out
    }

    // MARK: Guards in code (the small model does not reliably obey prompt rules)

    /// Words that count as the person having written something hard. A day is only allowed to carry a
    /// "difficult" point if its chosen mood is in `hardMoodIDs`, its score is 1 or 2, or its own words use one of
    /// these. "tired" is deliberately not here: tiredness is not automatically negative.
    static let difficultyLexicon: Set<String> = [
        "hard", "difficult", "stressful", "stressed", "stress", "anxious", "anxiety", "sad", "upset", "awful",
        "rough", "struggled", "struggle", "struggling", "cried", "crying", "angry", "worried", "worry", "worrying",
        "shaken", "overwhelmed", "overwhelming", "terrible", "painful", "lonely", "frustrated", "frustrating",
    ]
    static let hardMoodIDs: Set<String> = ["stressed", "annoyed"]

    /// Heaviness words the model tends to invent. A sentence using one survives only if the person's own words
    /// (for the cited days, or the whole week for the overview and questions) use the same word.
    static let heavinessLexicon: Set<String> = [
        "heavy", "heavier", "heaviness", "weight", "weary", "weariness", "effort", "drained", "draining",
        "exhausting", "exhausted", "struggle", "struggled", "struggling", "burden", "low", "sad", "anxious", "hard",
    ]

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "was", "were", "you", "your", "yours", "but", "had", "has",
        "have", "not", "all", "from", "into", "out", "its", "they", "them", "their", "there", "then", "than",
        "when", "what", "which", "while", "about", "after", "before", "just", "some", "more", "most", "very",
        "felt", "seem", "seems", "week", "day", "days", "also", "even", "still", "one", "two", "are", "been",
        "being", "who", "how", "why", "can", "could", "would", "should", "may", "might", "any", "our", "she",
        "him", "her", "his", "own", "too", "like", "got", "get", "over", "through", "again", "around",
    ]

    /// Everything the person wrote, per day and for the week, folded into comparable words.
    struct Evidence {
        private let perDay: [DateKey: Set<String>]
        private let week: Set<String>
        private let signalDays: Set<DateKey>

        init(_ input: ReflectionInput) {
            var perDay: [DateKey: Set<String>] = [:]
            var signals = Set<DateKey>()
            var all = Set(ReflectionSanitiser.words(ReflectionValidator.sourceText(input)))
            for d in input.days {
                var parts = [d.text] + [d.smileAnswer, d.rotatingAnswer].compactMap { $0 } + d.tagNames
                parts += input.followUps.filter { $0.writtenOn == d.dateKey }.map(\.note)
                parts += d.moodIDs.compactMap(MoodCatalog.label(for:))
                if let s = d.score.flatMap(DayScore.init(rawValue:)) { parts.append(s.label) }
                let words = Set(ReflectionSanitiser.words(parts.joined(separator: "\n")))
                perDay[d.dateKey] = words
                all.formUnion(words)
                let hardMood = d.moodIDs.contains { ReflectionSanitiser.hardMoodIDs.contains($0) }
                let hardScore = (d.score ?? 3) <= 2
                if hardMood || hardScore || !words.isDisjoint(with: ReflectionSanitiser.difficultyLexicon) {
                    signals.insert(d.dateKey)
                }
            }
            self.perDay = perDay
            self.week = all
            self.signalDays = signals
        }

        func hasDifficultySignal(_ keys: [DateKey]) -> Bool { keys.contains { signalDays.contains($0) } }

        /// True unless the sentence uses a heaviness word that none of the cited days' own words use.
        func allows(_ sentence: String, on keys: [DateKey]) -> Bool {
            let written = keys.reduce(into: Set<String>()) { $0.formUnion(perDay[$1] ?? []) }
            return Set(ReflectionSanitiser.words(sentence)).intersection(heavinessLexicon).isSubset(of: written)
        }

        func weekAllows(_ sentence: String) -> Bool {
            Set(ReflectionSanitiser.words(sentence)).intersection(heavinessLexicon).isSubset(of: week)
        }

        /// Shared content words between `text` and one day's own words.
        func overlap(_ text: String, on key: DateKey) -> Int {
            contentOverlap(ReflectionSanitiser.contentWords(text), perDay[key] ?? [])
        }

        func overlapDays(_ text: String) -> [DateKey: Int] {
            perDay.mapValues { contentOverlap(ReflectionSanitiser.contentWords(text), $0) }
        }

        private func contentOverlap(_ a: Set<String>, _ day: Set<String>) -> Int {
            a.intersection(ReflectionSanitiser.contentWords(day.joined(separator: " "))).count
        }
    }

    /// Second person, citation correction, heaviness and difficulty guards for highlight and difficult points.
    private static func grounded(
        _ source: [WeeklyReflectionContent.Point], _ evidence: Evidence, needsDifficultySignal: Bool
    ) -> [WeeklyReflectionContent.Point] {
        source.compactMap { p in
            var keys = p.dateKeys
            let counts = evidence.overlapDays(p.text)
            let best = keys.map { counts[$0] ?? 0 }.max() ?? 0
            if best < 2 {
                let stronger = counts.filter { $0.value >= 2 && $0.value > best && !keys.contains($0.key) }
                if stronger.count == 1, let only = stronger.first?.key {
                    keys = [only]
                } else if best == 0 {
                    return nil
                }
            }
            let text = filterSentences(p.text) { evidence.allows($0, on: keys) }
            if text.isEmpty { return nil }
            if needsDifficultySignal && !evidence.hasDifficultySignal(keys) { return nil }
            return .init(text: text, dateKeys: keys.sorted())
        }
    }

    // MARK: Words and sentences

    /// Lowercase, diacritic-folded whole words (apostrophes kept inside a word).
    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
        return folded.split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Words that carry meaning: stopwords and very short words removed, simple plural trimmed.
    static func contentWords(_ text: String) -> Set<String> {
        Set(
            words(text).compactMap { w in
                guard w.count >= 3, !stopwords.contains(w), !w.contains("'") else { return nil }
                return w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w
            })
    }

    /// Splits on . ! ? followed by space or the end, keeping the terminator with its sentence.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            if ".!?".contains(ch), i + 1 == chars.count || chars[i + 1].isWhitespace {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Rewrites each sentence to second person, drops any that still say "I" and any `keep` rejects.
    static func filterSentences(_ text: String, keep: (String) -> Bool) -> String {
        sentences(text).compactMap { sentence in
            guard let second = secondPerson(sentence) else { return nil }
            return keep(second) ? second : nil
        }.joined(separator: " ")
    }

    private static let personSwaps: [String: String] = [
        "my": "your", "me": "you", "myself": "yourself", "i'm": "you're", "i've": "you've",
    ]

    /// nil when the sentence has a standalone "i" left over ("you was" is never produced).
    static func secondPerson(_ sentence: String) -> String? {
        var out = ""
        var token = ""
        var standaloneI = false
        func flush() {
            guard !token.isEmpty else { return }
            let key = token.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
            if let swap = personSwaps[key] {
                let upper = token.first?.isUppercase == true
                out += upper ? swap.prefix(1).uppercased() + swap.dropFirst() : swap
            } else {
                if key == "i" || key == "i'll" || key == "i'd" { standaloneI = true }
                out += token
            }
            token = ""
        }
        for ch in sentence {
            if ch.isLetter || ch == "'" || ch == "\u{2019}" {
                token.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return standaloneI ? nil : out
    }

    private static func dedupe(_ points: [WeeklyReflectionContent.Point]) -> [WeeklyReflectionContent.Point] {
        var kept: [WeeklyReflectionContent.Point] = []
        for p in points {
            let isDuplicate = kept.contains { k in
                p.dateKeys.count == 1 && k.dateKeys == p.dateKeys && overlap(k.text, p.text) >= duplicateOverlap
            }
            if !isDuplicate { kept.append(p) }
        }
        return kept
    }

    /// Share of the shorter text's words that the other text also uses.
    static func overlap(_ a: String, _ b: String) -> Double {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let (x, y) = (words(a), words(b))
        let smaller = min(x.count, y.count)
        return smaller == 0 ? 0 : Double(x.intersection(y).count) / Double(smaller)
    }
}
