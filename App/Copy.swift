import Foundation
import ReytKit

/// All user-facing copy (A5). Lowercase, understated, no streaks or celebration.
enum Copy {
    enum Tab {
        static let today = "today"
        static let history = "history"
        static let reviews = "reviews"
        static let settings = "settings"
    }

    enum Placeholder {
        static let historyBody = "your past days will gather here."
        static let reviewsBody = "weekly reflections will gather here."
        static let settingsBody = "settings will live here."
    }

    enum Host {
        static let unlockPhone = "unlock your phone to open be reyt."
        static let openFailed =
            "be reyt couldn't open your journal. your entries are still on this phone, try closing and opening the app again."
    }

    enum Day {
        static let editorPlaceholder = "a little space for your day."
        static let editorLabel = "journal entry"
        static let scorePrompt = "how was your day?"
        static let scoreLabel = "day score"
        static let scoreNotSet = "not set"
        static let scoreClear = "clear score"
        static let moodsTitle = "moods"
        static let tagsTitle = "tags"
        static let previousDay = "previous day"
        static let nextDay = "next day"
        static let loadFailed = "couldn't open this day. tap to try again."

        static func scoreName(_ score: DayScore) -> String { score.label }

        /// "tuesday, 4 november 2026", lowercase, from the civil day.
        static func heading(for key: DateKey, calendar: Calendar = .current) -> String {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).day().month(.wide).year()
            return key.date(in: calendar).formatted(style).lowercased()
        }
    }

    enum Reflection {
        static let smileQuestion = "what made me smile today?"
        static let smileHelper = "a highlight, a small win, or just something you appreciated. small counts."
        static let smileAnswerLabel = "answer to what made me smile today"
        static let answerPlaceholder = "write here, or leave it blank."
        static let anotherPrompt = "another prompt"
        static let anotherPromptHint = "swaps today's reflection question for a different one"
        static let promptHelper = "optional. answer it only if it fits your day."
        static func promptAnswerLabel(_ question: String) -> String { "answer to \(question)" }
    }

    enum Tags {
        static let recentTitle = "recent"
        static let addPlaceholder = "add a tag"
        static let addLabel = "add tag"
        static let addFailed = "couldn't add that tag. try again in a moment."
        static func chipLabel(_ name: String, selected: Bool) -> String {
            selected ? "\(name), on this day" : "\(name), not on this day"
        }
    }

    enum Save {
        static let saving = "saving…"
        static let saved = "saved"
        static let failed = "couldn't save, tap to retry"
        static let indicatorLabel = "save status"
        static let retryHint = "tries saving your changes again"
    }

    enum Banner {
        static func expiry(daysLeft: Int) -> String {
            switch daysLeft {
            case ...0: "be reyt needs reinstalling from your mac now. your entries stay on your phone."
            case 1: "be reyt needs reinstalling from your mac in 1 day. your entries stay on your phone."
            default: "be reyt needs reinstalling from your mac in \(daysLeft) days. your entries stay on your phone."
            }
        }
    }
}
