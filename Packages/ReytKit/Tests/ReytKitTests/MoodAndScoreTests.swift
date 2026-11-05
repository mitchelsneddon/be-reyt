import Testing

@testable import ReytKit

@Suite("MoodCatalog")
struct MoodCatalogTests {
    @Test("catalog ids and labels")
    func catalog() {
        #expect(MoodCatalog.all.map(\.id) == ["happy", "stressed", "tired", "annoyed"])
        #expect(MoodCatalog.all.map(\.label) == ["happy", "stressed", "tired", "annoyed"])
        #expect(MoodCatalog.label(for: "tired") == "tired")
        #expect(MoodCatalog.label(for: "nope") == nil)
    }

    @Test("duplicates removed")
    func dedupe() {
        #expect(MoodCatalog.normalize(["tired", "tired", "happy", "happy"]) == ["happy", "tired"])
    }

    @Test("known ids follow catalog order")
    func order() {
        #expect(
            MoodCatalog.normalize(["annoyed", "tired", "stressed", "happy"]) == [
                "happy", "stressed", "tired", "annoyed",
            ])
    }

    @Test("unknown ids kept in first-seen order after known ones")
    func unknown() {
        #expect(
            MoodCatalog.normalize(["zen", "tired", "calm", "zen", "happy", "calm"]) == [
                "happy", "tired", "zen", "calm",
            ])
    }

    @Test("empty stays empty")
    func empty() {
        #expect(MoodCatalog.normalize([]).isEmpty)
    }
}

@Suite("DayScore")
struct DayScoreTests {
    @Test("out of range rejected", arguments: [-1, 0, 6, 100])
    func rejected(_ v: Int) {
        #expect(DayScore(v) == nil)
    }

    @Test("1...5 accepted with labels")
    func labels() {
        let expected = ["very difficult", "difficult", "okay", "good", "excellent"]
        for (i, label) in expected.enumerated() {
            #expect(DayScore(i + 1)?.label == label)
            #expect(DayScore(i + 1)?.rawValue == i + 1)
        }
    }
}
