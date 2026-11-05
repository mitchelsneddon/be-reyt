import FoundationModels
import ReytKit

/// The shape the on-device model fills in. Mirrors `WeeklyReflectionContent`; kept separate so ReytKit stays free
/// of FoundationModels. Dates come back as text and are checked by `ReflectionValidator` before anything is saved.
@Generable(description: "a gentle look back at one week of someone's private journal")
struct WeeklyReflection {
    @Guide(
        description:
            "two to four warm, tentative sentences about the week as a whole. no numbers, no counts, no dates, no advice."
    )
    var overview: String

    @Guide(
        description: "up to four moments that seemed good or meaningful, in the person's own terms",
        .maximumCount(4))
    var highlights: [ReflectionPointDraft]

    @Guide(
        description:
            "up to four moments that felt hard, said plainly and kindly, never turned into something positive. empty if nothing was hard",
        .maximumCount(4))
    var difficult: [ReflectionPointDraft]

    @Guide(
        description: "up to four things that came up on more than one day, each with the days that show it",
        .maximumCount(4))
    var themes: [ReflectionThemeDraft]

    @Guide(
        description:
            "at most two gentle, open questions inviting the person to look at their week. never advice, never about next week's wishes",
        .maximumCount(2))
    var questions: [String]
}

@Generable(description: "one moment from the week")
struct ReflectionPointDraft {
    @Guide(description: "one or two sentences. no numbers, no counts, no dates.")
    var text: String
    @Guide(
        description:
            "the days this is about, written exactly as in the day markers (yyyy-mm-dd). only days that appear.",
        .maximumCount(4))
    var dates: [String]
}

@Generable(description: "something that came up more than once")
struct ReflectionThemeDraft {
    @Guide(description: "two to five words, lowercase")
    var title: String
    @Guide(description: "one or two tentative sentences. no numbers, no counts, no dates.")
    var summary: String
    @Guide(
        description: "the days that support it, written exactly as in the day markers (yyyy-mm-dd)",
        .maximumCount(5))
    var dates: [String]
}

/// A short in-memory summary of one day (or one piece of a long day). Never stored.
@Generable(description: "a faithful short summary of one day of a journal")
struct DayDigest {
    @Guide(description: "one or two plain sentences saying what the person wrote. no interpretation.")
    var summary: String
    @Guide(description: "up to three short phrases for anything notable, including anything hard", .maximumCount(3))
    var notable: [String]
}

extension WeeklyReflection {
    var content: WeeklyReflectionContent {
        func keys(_ dates: [String]) -> [DateKey] {
            // An unreadable date maps to a day far outside any week, so the validator rejects it.
            dates.map { DateKey($0.trimmingCharacters(in: .whitespaces)) ?? DateKey(epochDay: 0) }
        }
        return WeeklyReflectionContent(
            overview: overview,
            highlights: highlights.map { .init(text: $0.text, dateKeys: keys($0.dates)) },
            difficult: difficult.map { .init(text: $0.text, dateKeys: keys($0.dates)) },
            themes: themes.map { .init(title: $0.title, summary: $0.summary, dateKeys: keys($0.dates)) },
            questions: questions)
    }
}
