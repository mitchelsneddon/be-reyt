import Foundation

/// Decides how a week's material fits the model's context window. Token counts are injected (the app passes the
/// model's own `tokenCount(for:)`), so the planning is testable. A day is never dropped: if the week does not fit
/// in one pass it is digested piece by piece, and if even that cannot work the honest answer is `.tooLong`.
public struct ContextBudget: Sendable {
    public typealias TokenCounter = @Sendable (String) async throws -> Int

    /// Room kept for the structured answer in a single pass.
    public static let reservedOutputTokens = 1200
    /// Room kept for one per-day digest answer.
    public static let digestReservedOutputTokens = 400
    /// Upper bound used when planning how big the digests will be when composed.
    public static let digestTokenCap = 200
    /// More digest calls than this will not finish inside the overall time limit.
    public static let maxDigestCalls = 24

    /// One day's material (or the plan and follow-up notes, which have no date key).
    public struct Segment: Sendable, Equatable {
        public let id: String
        public let dateKey: DateKey?
        public let text: String
        public init(id: String, dateKey: DateKey?, text: String) {
            self.id = id
            self.dateKey = dateKey
            self.text = text
        }
    }

    /// A piece of a segment that fits one digest call. Pieces of a segment are in order and together hold all of it.
    public struct Part: Sendable, Equatable {
        public let segmentID: String
        public let dateKey: DateKey?
        public let index: Int
        public let count: Int
        public let text: String
        public init(segmentID: String, dateKey: DateKey?, index: Int, count: Int, text: String) {
            self.segmentID = segmentID
            self.dateKey = dateKey
            self.index = index
            self.count = count
            self.text = text
        }
    }

    public enum Plan: Sendable, Equatable {
        case singlePass
        case digests([Part])
        case tooLong
    }

    public let contextSize: Int
    private let countTokens: TokenCounter

    public init(contextSize: Int, countTokens: @escaping TokenCounter) {
        self.contextSize = contextSize
        self.countTokens = countTokens
    }

    /// - Parameters:
    ///   - singlePassFixedTokens: instructions plus schema for the one-pass call.
    ///   - singlePassPrompt: the whole prompt for the one-pass call.
    ///   - digestFixedTokens: instructions plus schema for a digest call.
    ///   - composeFixedTokens: instructions, schema and facts for the final call that reads the digests.
    public func plan(
        singlePassFixedTokens: Int, singlePassPrompt: String, digestFixedTokens: Int, composeFixedTokens: Int,
        segments: [Segment]
    ) async throws -> Plan {
        let single = try await countTokens(singlePassPrompt)
        if singlePassFixedTokens + single + Self.reservedOutputTokens <= contextSize { return .singlePass }

        let partBudget = contextSize - digestFixedTokens - Self.digestReservedOutputTokens
        guard partBudget > 0 else { return .tooLong }

        var parts: [Part] = []
        for segment in segments {
            let pieces = try await split(segment.text, budget: partBudget)
            for (i, piece) in pieces.enumerated() {
                parts.append(
                    Part(
                        segmentID: segment.id, dateKey: segment.dateKey, index: i, count: pieces.count, text: piece))
            }
            if parts.count > Self.maxDigestCalls { return .tooLong }
        }
        let estimated = composeFixedTokens + parts.count * Self.digestTokenCap + Self.reservedOutputTokens
        return estimated <= contextSize ? .digests(parts) : .tooLong
    }

    /// True when the real composed prompt (after the digests exist) fits with room for the answer.
    public func composeFits(fixedTokens: Int, prompt: String) async throws -> Bool {
        fixedTokens + (try await countTokens(prompt)) + Self.reservedOutputTokens <= contextSize
    }

    // MARK: Splitting

    /// Packs paragraphs into pieces under `budget`; a paragraph that alone overflows is halved at whitespace.
    func split(_ text: String, budget: Int) async throws -> [String] {
        if try await countTokens(text) <= budget { return [text] }
        var pieces: [String] = []
        var current: [String] = []
        var currentTokens = 0
        func flush() {
            if !current.isEmpty { pieces.append(current.joined(separator: "\n\n")) }
            current = []
            currentTokens = 0
        }
        for paragraph in text.components(separatedBy: "\n\n") where !paragraph.isEmpty {
            for fit in try await halve(paragraph, budget: budget) {
                let n = try await countTokens(fit) + 2
                if currentTokens + n > budget { flush() }
                current.append(fit)
                currentTokens += n
            }
        }
        flush()
        return pieces.isEmpty ? [text] : pieces
    }

    private func halve(_ text: String, budget: Int) async throws -> [String] {
        if text.count <= 1 { return [text] }
        if try await countTokens(text) <= budget { return [text] }
        let mid = text.index(text.startIndex, offsetBy: text.count / 2)
        // Prefer to cut at the nearest whitespace after the midpoint so words stay whole.
        var cut = text[mid...].firstIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? mid
        if cut == text.endIndex { cut = mid }
        let head = String(text[..<cut])
        let tail = String(text[cut...])
        if head.isEmpty || tail.isEmpty { return [text] }
        return try await halve(head, budget: budget) + halve(tail, budget: budget)
    }
}
