import Foundation

/// The stored narrative for one review week: plain words the on-device model wrote, nothing computed.
/// Numbers, counts and charts never live here (they come from `WeeklyStats`). Dates cite entries in the week.
public struct WeeklyReflectionContent: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var text: String
        public var dateKeys: [DateKey]
        public init(text: String, dateKeys: [DateKey]) {
            self.text = text
            self.dateKeys = dateKeys
        }
    }

    public struct Theme: Codable, Sendable, Equatable {
        public var title: String
        public var summary: String
        public var dateKeys: [DateKey]
        public init(title: String, summary: String, dateKeys: [DateKey]) {
            self.title = title
            self.summary = summary
            self.dateKeys = dateKeys
        }
    }

    public var overview: String
    public var highlights: [Point]
    public var difficult: [Point]
    public var themes: [Theme]
    /// At most two gentle questions. The model never answers the user's "more of this" question.
    public var questions: [String]

    public init(overview: String, highlights: [Point], difficult: [Point], themes: [Theme], questions: [String]) {
        self.overview = overview
        self.highlights = highlights
        self.difficult = difficult
        self.themes = themes
        self.questions = questions
    }

    public func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(json: String) -> WeeklyReflectionContent? {
        try? JSONDecoder().decode(WeeklyReflectionContent.self, from: Data(json.utf8))
    }
}
