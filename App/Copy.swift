import Foundation
import ReytKit

/// All user-facing copy (A5). Lowercase, understated, no streaks or celebration.
enum Copy {
    /// The one day-first, lowercase date formatter: "mon 26 oct 2026", "5 november", "wed 4 nov". Month and weekday
    /// names come from the calendar's locale, the order never does.
    enum Dates {
        enum Width { case abbreviated, wide }

        static func format(
            _ date: Date, weekday: Width? = nil, month: Width = .wide, year: Bool = false, calendar: Calendar = .current
        ) -> String {
            func part(_ style: Date.FormatStyle) -> String { date.formatted(style).lowercased() }
            let base = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            var parts: [String] = []
            if let weekday { parts.append(part(base.weekday(weekday == .wide ? .wide : .abbreviated))) }
            parts.append(String(calendar.component(.day, from: date)))
            parts.append(part(base.month(month == .wide ? .wide : .abbreviated)))
            if year { parts.append(String(calendar.component(.year, from: date))) }
            return parts.joined(separator: " ")
        }

        static func format(
            _ key: DateKey, weekday: Width? = nil, month: Width = .wide, year: Bool = false,
            calendar: Calendar = .current
        ) -> String {
            format(key.date(in: calendar), weekday: weekday, month: month, year: year, calendar: calendar)
        }
    }

    enum Tab {
        static let today = "today"
        static let history = "history"
        static let reviews = "reviews"
        static let settings = "settings"
    }

    enum History {
        static let modeLabel = "history view"
        static let calendar = "calendar"
        static let list = "list"
        static let emptyJournal = "nothing here yet."
        static let noMatches = "nothing matches that."
        static let searchPrompt = "search your days"
        static let tagFilterLabel = "filter by tag"
        static let calendarLabel = "calendar of your days"
        static let loadFailed = "couldn't open your history. tap to try again."
        static let hasEntry = "has an entry"
        static let clearSearch = "clear search"
        static let scoreKey = "day score key"

        /// "november 2026", lowercase.
        static func monthHeader(year: Int, month: Int, calendar: Calendar = .current) -> String {
            guard let key = DateKey(year: year, month: month, day: 1) else { return "" }
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
            return key.date(in: calendar).formatted(style).lowercased()
        }

        /// "wed 4 nov", lowercase.
        static func rowDate(_ key: DateKey, calendar: Calendar = .current) -> String {
            Dates.format(key, weekday: .abbreviated, month: .abbreviated, calendar: calendar)
        }

        /// "thu", lowercase.
        static func weekdayShort(_ key: DateKey, calendar: Calendar = .current) -> String {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            return key.date(in: calendar).formatted(style).lowercased()
        }

        static func photosLabel(_ n: Int) -> String { n == 1 ? "1 photo" : "\(n) photos" }
        static func moodsLabel(_ n: Int) -> String { n == 1 ? "1 mood" : "\(n) moods" }
        static func scoreLabel(_ score: DayScore) -> String { "day score, \(score.label)" }
        static func rowLabel(date: String, preview: String) -> String {
            preview.isEmpty ? date : "\(date), \(preview)"
        }
    }

    enum Host {
        static let unlockPhone = "unlock your phone to open be reyt."
        static let openFailed =
            "be reyt couldn't open your journal. your entries are still on this phone, try closing and opening the app again."
    }

    enum Lock {
        static let appName = "be reyt"
        static let tagline = "a little space for your day."
        static let unlock = "unlock"
        static let unlockHint = "opens your journal with face id or your passcode"
        static let reason = "unlock your journal."
        static let noPasscode = "set a device passcode to lock be reyt."
    }

    enum Day {
        static let entryTitle = "how was your day?"
        static let editorPlaceholder = "tell me about it."
        static let editorLabel = "journal entry"
        static let scoreTitle = "how was your day?"
        static let feelTitle = "how did you feel today?"
        static let scoreLabel = "day score"
        static let scoreNotSet = "not set"
        static let scoreClear = "clear score"
        static let previousDay = "previous day"
        static let nextDay = "next day"
        static let loadFailed = "couldn't open this day. tap to try again."

        static func scoreName(_ score: DayScore) -> String { score.label }

        /// "thursday · week 45", lowercase, from the civil day.
        static func eyebrow(for key: DateKey, calendar: Calendar = .current) -> String {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
            return "\(key.date(in: calendar).formatted(style).lowercased()) · week \(key.isoWeek)"
        }

        /// "5 november", lowercase; "5 november 2024" when the day is not in the current year.
        static func dateTitle(
            for key: DateKey, currentYear: Int = AppClock.today().year, calendar: Calendar = .current
        ) -> String {
            Dates.format(key, year: key.year != currentYear, calendar: calendar)
        }

        /// The spoken version of the header, always with the year.
        static func headerLabel(for key: DateKey, calendar: Calendar = .current) -> String {
            "\(eyebrow(for: key, calendar: calendar)), \(Dates.format(key, year: true, calendar: calendar))"
        }
    }

    enum Reviews {
        static let title = "reviews"
        static let thisWeeksReview = "this week's review"
        static let loadFailed = "couldn't open your reviews. tap to try again."
        static let weekdayShort = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

        static func weekOf(_ range: String) -> String { "week of \(range)" }
        /// "week of 1 nov", from the week's Sunday.
        static func weekOfStart(_ key: DateKey, calendar: Calendar = .current) -> String {
            weekOf(Dates.format(key, month: .abbreviated, calendar: calendar))
        }
        static func coverage(_ recorded: Int) -> String { "\(recorded) of 7 days recorded" }
        static func rowLabel(week: String, coverage: String, isLatest: Bool) -> String {
            isLatest ? "\(thisWeeksReview), \(week), \(coverage)" : "\(week), \(coverage)"
        }

        /// "your first review opens on sunday 8 nov."
        static func emptyList(opensOn key: DateKey, calendar: Calendar = .current) -> String {
            "your first review opens on \(Dates.format(key, weekday: .wide, month: .abbreviated, calendar: calendar))."
        }

        static let emptyWeek = "nothing was written this week."

        static let feltTitle = "how the week felt"
        static let smileTitle = "what made you smile"
        static let followUpTitle = "how did that go?"
        static let activitiesTitle = "activities"
        static let feelingsTitle = "feelings this week"
        static let nextWeekTitle = "next week"
        static func youPlanned(_ text: String) -> String { "you planned: “\(text)”" }
        static let timeLabel = "time"
        static let distanceLabel = "distance"
        static let thisWeek = "this week"
        static let yourWeek = "your week"
        static let noScore = "no score"
        static let dayScoresLabel = "day scores, sunday to saturday"
        static let weekdayLong = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        static let weekdayInitials = ["s", "m", "t", "w", "t", "f", "s"]

        /// "sunday · week 45": the Sunday the review opens, and its ISO week.
        static func eyebrow(weekStart: DateKey, calendar: Calendar = .current) -> String {
            Day.eyebrow(for: WeekCalendar.unlockKey(forWeekStart: weekStart), calendar: calendar)
        }

        /// "1 to 7 november", or "26 october to 1 november" across a month.
        static func range(from start: DateKey, to end: DateKey, calendar: Calendar = .current) -> String {
            func month(_ key: DateKey) -> String {
                key.date(in: calendar).formatted(
                    Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide)
                ).lowercased()
            }
            if start.month == end.month { return "\(start.day) to \(end.day) \(month(end))" }
            return "\(start.day) \(month(start)) to \(end.day) \(month(end))"
        }

        /// "monday, good" or "monday, no score".
        static func dayFaceLabel(weekday: Int, score: DayScore?) -> String {
            "\(weekdayLong[weekday]), \(score?.label ?? noScore)"
        }

        /// "happy, 4".
        static func feelingLabel(_ label: String, count: Int) -> String { "\(label), \(count)" }

        /// "mostly good days. happy came up four times. a little brighter than last week."
        static func weekFeel(_ feel: WeekFeel, moodLabel: (String) -> String) -> String {
            var parts: [String] = []
            if let band = feel.band {
                switch band {
                case .difficult: parts.append("mostly difficult days.")
                case .mixed: parts.append("a mixed week.")
                case .okay: parts.append("mostly okay days.")
                case .good: parts.append("mostly good days.")
                case .great: parts.append("a really good week.")
                }
            }
            if let top = feel.topMood {
                let words = ["one", "two", "three", "four", "five", "six", "seven"]
                let label = moodLabel(top.id)
                if top.dayCount == 1 {
                    parts.append("\(label) came up once.")
                } else {
                    let n = (2...7).contains(top.dayCount) ? words[top.dayCount - 1] : "\(top.dayCount)"
                    parts.append("\(label) came up \(n) times.")
                }
            }
            if let direction = feel.direction {
                switch direction {
                case .brighter: parts.append("a little brighter than last week.")
                case .similar: parts.append("much like last week.")
                case .harder: parts.append("a little harder than last week.")
                }
            }
            return parts.joined(separator: " ")
        }

        static let openDayHint = "opens that day"
    }

    enum Reflection {
        static let smileQuestion = "what made me smile today?"
        static let smileAnswerLabel = "answer to what made me smile today"
        static let answerPlaceholder = "write here, or leave it blank."
        static let smilePlaceholder = "even a small thing."
        static let anotherPrompt = "another prompt"
        static let anotherPromptHint = "swaps today's reflection question for a different one"
        static func promptAnswerLabel(_ question: String) -> String { "answer to \(question)" }
    }

    enum Plan {
        static let question = "what's one thing you want or need to do next week?"
        static let answerLabel = "answer to what's one thing you want or need to do next week"
        /// Stable stored IDs (persisted in WeeklyIntention.category) paired with display labels.
        static let categories: [(id: String, label: String)] = [
            ("looking-forward-to", "looking forward to"),
            ("goal", "goal"),
            ("need-to-do", "need to do"),
            ("want-to-do", "want to do"),
        ]
        /// Display label for a stored category ID; unknown IDs (e.g. from a newer version) show as stored.
        static func categoryLabel(for id: String) -> String {
            categories.first { $0.id == id }?.label ?? id
        }
        static let categoriesLabel = "kind of thing, optional"
        static let thisWeekTitle = "this week"
        static func rangeTitle(_ range: String) -> String { range }
        static let editPlan = "edit your plan"
        static let editPlanHint = "opens the sunday you wrote it"

        static let followUpTitle = "how did that go?"
        static func followUpQuote(_ plan: String) -> String { "you planned: “\(plan)”" }
        static let followUpPlaceholder = "a note, if you like."
        static let followUpNoteLabel = "note on how that went"
        static let skip = "skip"
        static let skipHint = "leaves this one without a note"
        static let edit = "edit"
        static let done = "done"
        static let skipped = "skipped"
    }

    enum Tags {
        static let addAffordance = "+ add a tag"
        static let addPlaceholder = "add a tag"
        static let addLabel = "add tag"
        static let addFailed = "couldn't add that tag. try again in a moment."
        static let manageLink = "manage tags"
        static let manageTitle = "tags"
        static let manageEmpty = "no tags yet."
        static func usedOn(_ days: Int) -> String { days == 1 ? "used on 1 day" : "used on \(days) days" }
        static func rowLabel(_ name: String, days: Int) -> String { "\(name), \(usedOn(days))" }
        static let rowHint = "opens rename"
        static let renameTitle = "rename tag"
        static let renameField = "tag name"
        static let renameBlank = "a tag needs a name."
        static func renameTaken(_ name: String) -> String { "you already have a tag called \(name)." }
        static let renameFailed = "couldn't rename that tag. try again in a moment."
        static func deleteConfirm(_ name: String) -> String {
            "remove “\(name)” from every day? the days themselves stay."
        }
        static let deleteAction = "remove"
        static let keep = "keep it"
        static let deleteFailed = "couldn't remove that tag. try again in a moment."
        static let ok = "ok"
        static let cancel = "cancel"
        static let save = "save"
        static let done = "done"
        static let edit = "edit"
        static let settingsRow = "tags"
        static let journalSection = "journal"
        static func chipLabel(_ name: String, selected: Bool) -> String {
            selected ? "\(name), on this day" : "\(name), not on this day"
        }
    }

    enum Photos {
        static let title = "photos"
        static let add = "add photos"
        static let addShort = "add"
        static let beingAdded = "photo being added"
        static let addHint = "choose photos from your library"
        static func thumbnailLabel(_ index: Int, of count: Int) -> String { "photo \(index) of \(count)" }
        static func counter(_ index: Int, of count: Int) -> String { "\(index) of \(count)" }
        /// "thursday 5 november", lowercase, under the photo.
        static func viewerDate(_ key: DateKey, calendar: Calendar = .current) -> String {
            Dates.format(key, weekday: .wide, calendar: calendar)
        }
        static let thumbnailHint = "opens the photo full screen"
        static let close = "close"
        static let remove = "remove photo"
        static let removeConfirm = "remove this photo from the day?"
        static let removeAction = "remove"
        static let keep = "keep it"
        static func importing(_ current: Int, of total: Int) -> String {
            total == 1 ? "bringing in your photo…" : "bringing in photo \(current) of \(total)…"
        }
        static let unsupported = "that isn't a kind of photo be reyt can keep."
        static let importFailed = "couldn't bring in this photo. try again when it's downloaded."
        static func importFailedMany(_ count: Int) -> String {
            "couldn't bring in \(count) photos. try again when they're downloaded."
        }
        static let storageFull = "there isn't enough space on this phone for that photo. free some up and try again."
        static let removeFailed = "couldn't remove that photo. try again in a moment."
        static let loadFailed = "couldn't show this photo."
    }

    enum Workouts {
        static let title = "workouts"
        static let activitiesTitle = "activities"

        /// "17:40", the start time shown on a card.
        static func startTime(_ date: Date) -> String {
            date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        /// "1 h 16 min", "45 min", "2 h".
        static func duration(seconds: Double) -> String {
            let total = Int((seconds / 60).rounded())
            let hours = total / 60
            let minutes = total % 60
            if hours == 0 { return "\(max(minutes, 1)) min" }
            return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
        }

        /// "12.3 km" or "7.6 mi" by locale; swims stay in metres or yards.
        static func distance(meters: Double, swimming: Bool) -> String {
            let measurement = Measurement(value: meters, unit: UnitLength.meters)
            if swimming {
                return measurement.formatted(
                    .measurement(
                        width: .abbreviated, usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(0))))
            }
            return measurement.formatted(
                .measurement(
                    width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }

        static func cardLabel(name: String, duration: String, distance: String?) -> String {
            [name, duration, distance].compactMap { $0 }.joined(separator: ", ")
        }
    }

    enum Health {
        static let section = "apple health"
        static let unavailable = "health isn't available on this device."
        static let asked = "be reyt has asked to read your workouts."
        static let allow = "allow access to workouts"
        static let allowHint = "shows the ios health permission sheet"
        static let nothingFound = "no workouts found, or health access is off."
    }

    enum Reminder {
        static let section = "reminder"
        static let toggle = "remind me in the evening"
        static let time = "time"
        static func hourLabel(_ hour: Int) -> String {
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            return "\(h12) \(hour < 12 ? "am" : "pm")"
        }
        static let allow = "allow notifications"
        static let allowHint = "shows the ios notification permission sheet"
        static let denied = "notifications are off for be reyt, so the reminder can't show."
        static let openSettings = "open ios settings"
        static let openSettingsHint = "opens the notification settings for be reyt"
        static let notificationTitle = "be reyt"
        static let notificationBody = "a little space for your day, if you'd like it."
    }

    enum Save {
        static let saving = "saving…"
        static let saved = "saved"
        static let failed = "couldn't save, tap to retry"
        static let indicatorLabel = "save status"
        static let retryHint = "tries saving your changes again"
    }

    enum Shared {
        static let dismiss = "dismiss"
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

    enum WeekReflection {
        static let title = "reflection"
        static let write = "write my reflection"
        static let writeHint = "writes a short reflection on this phone with apple's on-device model"
        static let generating = "writing your reflection…"
        static let regenerate = "regenerate"
        static let regenerateHint = "writes the reflection again with the newer wording"
        static let tryAgain = "try again"
        static let footnote = "written on this phone. it can get things wrong."
        static let purged = "this week changed, so the reflection was cleared."
        static let highlights = "highlights"
        static let difficult = "what felt difficult"
        static let themes = "recurring themes"
        static let questions = "to sit with"

        static func failure(_ failure: ReflectionFailure) -> String {
            switch failure {
            case .deviceNotEligible:
                "this iphone can't run apple's on-device model, so there's no written reflection."
            case .appleIntelligenceNotEnabled:
                "turn on apple intelligence in settings to write a reflection."
            case .modelNotReady:
                "the on-device model is still downloading. try again in a little while."
            case .unsupportedLanguage:
                "the on-device model doesn't support this language yet, so there's no written reflection."
            case .guardrail:
                "the on-device model couldn't write a reflection for this week."
            case .refused:
                "the on-device model chose not to write about this week."
            case .tooLong:
                "this week has more writing than the on-device model can read at once, so there's no reflection."
            case .timedOut:
                "that took too long, so it was stopped. try again."
            case .rateLimited, .busy:
                "the on-device model is busy. try again in a moment."
            case .unreadableAnswer, .invalidAnswer, .modelError:
                "couldn't write a reflection this time. try again."
            case .cancelled:
                "couldn't finish that one. try again."
            case .changedWhileWriting:
                "this week changed while writing, try again."
            case .couldNotSave:
                "couldn't save the reflection. try again."
            case .noEntries:
                "nothing was written this week, so there's nothing to reflect on."
            }
        }
    }

    enum Settings {
        static let title = "settings"
        static let aiSection = "on-device ai"
        static let aiRow = "apple's on-device model"
        static let aiAvailable = "available"
        static let aiTurnOn = "turn on apple intelligence in settings"
        static let aiDownloading = "the model is still downloading"
        static let aiNotSupported = "not supported on this iphone"
        static let aiLanguage = "not available in this language"
        static let problem = "problem"
        static let backupSection = "backup passphrase & files"
        static let passphraseRow = "backup passphrase"
        static let passphraseSet = "set"
        static let passphraseNotSet = "not set yet"
        static let exportRow = "export a backup"
        static let exportRowNeedsPassphrase = "set a passphrase first"
        static let restoreRow = "restore from a file"
        static let undoRow = "undo last restore"
        static let undoHint = "goes back to what was on this phone before the last restore"
        static let displaySection = "display"
        static let appearance = "appearance"
        static let appearanceSystem = "system"
        static let appearanceLight = "light"
        static let appearanceDark = "dark"
    }

    enum Hub {
        static let lockSection = "app lock"
        static let lockRow = "locks when you leave"
        static let lockOn = "on"
        static let lockOff = "can't lock"
        static let lockNoPasscode =
            "this phone has no passcode, so be reyt can't lock. set one in ios settings to turn the lock on."
        static let readableSection = "readable exports"
        static let privacySection = "privacy"
        static let privacyLines = [
            "nothing leaves your phone except backups you choose.",
            "no account, no analytics.",
            "reflections are written on this phone.",
            "deleted things can stay in your backups for up to 30 days.",
        ]
        static let aboutSection = "about"
        static let version = "version"
        static let signedUntil = "signed until"
        static func versionValue(version: String, build: String) -> String { "\(version) (\(build))" }
    }

    enum PassphraseQuestion {
        static let useTypedTitle = "use this passphrase for future backups?"
        static let useTypedMessage =
            "this phone doesn't have a backup passphrase yet. you can use the one you just typed, or set one later."
        static let useTypedYes = "yes, use it"
        static let useTypedNo = "no, leave it unset"
        static let switchTitle = "keep your current backup passphrase?"
        static let switchMessage =
            "the one you just typed is different from the one this phone uses for backups. switching will start a fresh backup protected by the new one."
        static let keep = "keep current"
        static let switchTo = "switch to the passphrase you just typed"
        static let saveFailed = "couldn't save the passphrase on this phone. you can set one in settings."
    }

    enum Passphrase {
        static let setTitle = "backup passphrase"
        static let changeTitle = "change passphrase"
        static let warning =
            "write this down somewhere safe. without it, your backups can't be opened."
        static let current = "current passphrase"
        static let new = "new passphrase"
        static let confirm = "type it again"
        static let save = "save passphrase"
        static let cancel = "cancel"
        static let tooShort = "use at least 8 characters."
        static let mismatch = "those two don't match."
        static let wrongCurrent = "that isn't your current passphrase."
        static let saveFailed = "couldn't save the passphrase on this phone. try again in a moment."
        static let reauthReason = "confirm it's you to change your backup passphrase."
    }

    enum Export {
        static let working = "gathering your journal…"
        static let reauthFailed = "couldn't confirm it's you, so nothing was exported."
        static let failed = "couldn't make the backup. nothing was changed, try again in a moment."
        static let storageFull =
            "there isn't enough space on this phone to make the backup. free some up and try again."
        static let saved = "backup saved."
        static func skipped(_ photos: Int) -> String {
            photos == 1 ? "1 photo couldn't be included." : "\(photos) photos couldn't be included."
        }
        static let exporterError = "couldn't save the backup there. try another place."
        static func fileSize(_ bytes: Int?) -> String? { RestoreBrowser.size(bytes) }
    }

    enum Restore {
        static let title = "restore"
        static let enterPassphrase = "enter the passphrase for this backup."
        static let passphraseField = "passphrase"
        static let open = "open backup"
        static let cancel = "cancel"
        static let opening = "opening your backup…"
        static let previewTitle = "this backup"
        static let previewIntro = "it holds"
        static func days(_ n: Int) -> String { n == 1 ? "1 day written" : "\(n) days written" }
        static func photos(_ n: Int) -> String { n == 1 ? "1 photo" : "\(n) photos" }
        static func tags(_ n: Int) -> String { n == 1 ? "1 tag" : "\(n) tags" }
        static func plans(_ n: Int) -> String { n == 1 ? "1 sunday plan" : "\(n) sunday plans" }
        static func range(first: String, last: String) -> String { "from \(first) to \(last)" }
        static func fileDate(_ date: Date) -> String { Dates.format(date, year: true) }
        static let replace = "replace everything on this phone with this backup"
        static let confirmTitle = "replace everything on this phone with this backup?"
        static let confirmAction = "replace"
        static let confirmMessage =
            "what's here now will be saved as a safety copy first, and you can undo for 7 days."
        static let reauthReason = "confirm it's you to restore from a backup."
        static let reauthFailed = "couldn't confirm it's you, so nothing was changed."
        static let restoring = "restoring your journal…"
        static let undoing = "going back…"
        static let tryAgain = "try again"
        static let close = "close"
        static func doneNote(entries: Int) -> String {
            entries == 0
                ? "restored from your backup."
                : entries == 1 ? "restored. 1 day is back." : "restored. \(entries) days are back."
        }
        static let undoneNote = "back to what was here before the restore."
        static let undoConfirmTitle = "go back to what was here before the last restore?"
        static let undoConfirmMessage =
            "anything you've written since the restore will be saved as a safety copy, then replaced."
        static let undoAction = "go back"
        static let dismiss = "dismiss"

        static func failure(_ failure: RestoreFailure) -> String {
            switch failure {
            case .wrongPassphrase:
                "that passphrase didn't open this backup. check it and try again, nothing was changed."
            case .notABackup: "that file isn't a be reyt backup. nothing was changed."
            case .newerVersion:
                "this backup was made by a newer version of be reyt. update the app and try again."
            case .damaged: "this backup looks damaged and can't be restored. nothing was changed."
            case .noPassphrase:
                "set a backup passphrase first, so what's on this phone can be saved before it's replaced."
            case .safetyCopyFailed:
                "couldn't save a safety copy first, so nothing was changed. try again in a moment."
            case .switchFailed: "something went wrong, so nothing was changed. try again in a moment."
            case .photoUnreadable: "a photo in this backup couldn't be read, so nothing was changed."
            case .folderMissing:
                "the backup folder couldn't be found. choose it again in automatic backups. nothing was changed."
            case .unreachable:
                "couldn't reach that backup. if it's in icloud, check your connection and try again. nothing was changed."
            case .busy: "a restore is already running."
            case .nothingToUndo: "there's nothing to go back to."
            }
        }
    }

    /// Restoring from a snapshot in the automatic-backup folder.
    enum RestoreBrowser {
        static let row = "restore from a backup"
        static let rowHint = "pick one of the backups in your backup folder"
        static let title = "restore from a backup"
        static let loading = "looking in your backup folder…"
        static let empty = "no backups in this folder yet."
        static let loadFailed = "couldn't read the backup folder. check it still exists and try again."
        static let retry = "try again"
        static let savedBeforeRestore = "saved before a restore"
        static let onThisPhone = "on this iphone"
        static let inICloud = "in icloud"
        static let enterPassphrase =
            "enter the passphrase for this backup. an older backup may need the passphrase you had back then."

        static func day(_ key: DateKey, calendar: Calendar = .current) -> String {
            History.rowDate(key, calendar: calendar)
        }

        static func size(_ bytes: Int?) -> String? {
            bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file).lowercased() }
        }

        static func rowLabel(day: String, size: String?, kind: String?, location: String) -> String {
            [day, kind, size, location].compactMap { $0 }.joined(separator: ", ")
        }
    }

    enum ReadableExport {
        static let row = "readable exports"
        static let rowHint = "make a markdown or pdf copy of your journal that you can read anywhere"
        static let title = "readable exports"
        static let markdownRow = "export as markdown"
        static let pdfRow = "export as pdf"
        static let notEncrypted = "readable exports aren't encrypted. keep them somewhere private."
        static let rangeSection = "which days"
        static let rangeLabel = "days to include"
        static let rangeAll = "all days"
        static let rangeCustom = "pick dates"
        static let startLabel = "from"
        static let endLabel = "to"
        static let workoutsToggle = "include workouts"
        static let working = "putting it together…"
        static let saved = "export saved."
        static let nothing = "there's nothing to export for those days."
        static let failed = "couldn't make the export. nothing was changed, try again in a moment."
        static let storageFull =
            "there isn't enough space on this phone to make the export. free some up and try again."
        static let exporterError = "couldn't save the export there. try another place."
        static func progress(_ percent: Int) -> String { "writing the pdf, \(percent)%…" }
    }

    enum Import {
        static let settingsSection = "apple journal"
        static let row = "import from apple journal"
        static let rowHint = "choose the unzipped AppleJournalEntries folder"
        static let title = "import from apple journal"
        static let close = "close"
        static let cancel = "cancel"
        static let importAction = "import"
        static let done = "done"
        static let readingTitle = "reading your export…"
        static func progress(done: Int, total: Int) -> String { "\(done) of \(total) entries" }
        static let importingTitle = "adding to your journal…"
        static let noTimes = "dates and titles kept, times aren't in the export."
        static let nothingNew = "nothing new to import."
        static let nothingNewDetail = "every entry in this export is already in your journal."
        static func entries(_ n: Int) -> String { n == 1 ? "1 entry" : "\(n) entries" }
        static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        static func photos(_ n: Int) -> String { n == 1 ? "1 photo" : "\(n) photos" }
        static func summary(entries: Int, days: Int) -> String {
            "\(Self.entries(entries)) on \(Self.days(days))"
        }
        static func range(first: String, last: String) -> String { "\(first) to \(last)" }
        static let willImportSection = "will be added"
        static let alreadyImportedSection = "already imported"
        static func alreadyImported(_ n: Int) -> String {
            n == 1
                ? "1 entry is already in your journal and will be skipped."
                : "\(n) entries are already in your journal and will be skipped."
        }
        static let unsupportedSection = "left out"
        static let fallbackNote =
            "some entries had no readable date, so the date in the file name was used (one day earlier, as the export names files)."
        static let conflictsSection = "days that already have writing"
        static let append = "add after mine"
        static let skip = "skip"
        static func conflictLabel(_ day: String) -> String { "choose for \(day)" }
        static let failuresSection = "couldn't be read"
        static func failure(_ reason: AppleJournalParseFailure.Reason) -> String {
            switch reason {
            case .notAnEntry: "doesn't look like a journal entry"
            case .unreadable: "couldn't be opened"
            case .tooLarge: "too large"
            case .symbolicLink: "a shortcut, not a real file"
            case .noDate: "no date found"
            }
        }
        static let resultTitle = "import finished"
        static func resultLine(entries: Int, days: Int) -> String {
            "added \(Self.entries(entries)) across \(Self.days(days))."
        }
        static func photosResult(imported: Int, failed: Int) -> String? {
            if imported == 0, failed == 0 { return nil }
            if failed == 0 { return imported == 1 ? "1 photo added." : "\(imported) photos added." }
            return "\(imported) added, \(failed) couldn't be added. the writing is saved either way."
        }

        static func error(_ error: AppleJournalParseError) -> String {
            switch error {
            case .noEntriesFolder:
                "that folder doesn't have an Entries folder inside. choose the unzipped AppleJournalEntries folder."
            case .unsafeFolder: "that folder isn't safe to read, so nothing was changed."
            case .tooManyFiles: "that folder has more files than be reyt will read, so nothing was changed."
            case .tooLarge: "that export is larger than be reyt will read, so nothing was changed."
            case .cancelled: "the import was cancelled, nothing was changed."
            }
        }
        static let genericError = "something went wrong, so nothing was changed. try again in a moment."
        static let noAccess = "be reyt couldn't open that folder, so nothing was changed. try choosing it again."
    }

    enum Onboarding {
        static let wordmarkStart = "be"
        static let wordmarkEnd = "reyt"
        static let wordmark = "be reyt"
        static func stepLabel(_ step: Int) -> String { "step \(step) of 3" }
        static let continueButton = "continue"
        static let notNow = "not now"

        static let reminderTitle = "a reminder in the evening?"
        static let workoutsTitle = "your workouts, beside your day?"
        static let backupsTitle = "keep a backup?"

        static let allowWorkouts = "allow access to workouts"
        static let previewName = "yoga"
        static let previewDuration = "25 min"
        static let previewTime = "07:15"

        static let chooseFolder = "choose a backup folder"
        static let folderRow = "backup folder"
        static let notSetUp = "not set up"
        static let passphraseRow = "backup passphrase"
        static let notSetYet = "not set yet"
        static let isSet = "set"
        static let chooseFolderHint = "opens the files picker so you can pick a folder, ideally in icloud drive"
        static let passphraseHint = "opens a sheet to choose a backup passphrase"
        static let phoneOnly = "without a backup, your journal lives only on this phone."
        static let startWriting = "start writing"
        static let later = "later"
    }

    enum DeleteAll {
        static let row = "delete all data"
        static let rowHint = "removes everything be reyt keeps on this phone"
        static let title = "delete all data"
        static let removesHeader = "this removes, from this phone"
        static let removes = [
            "every entry, photo, reflection and plan",
            "your tags and settings",
            "the backup passphrase stored on this phone",
            "scheduled reminders",
        ]
        static let keepsHeader = "this does not remove"
        static let keeps = [
            "backup files you've saved. delete those yourself in the files app.",
            "apple health data. be reyt only reads it.",
        ]
        static let irreversible = "this can't be undone. be reyt will be empty, as if you'd just installed it."
        static let reauthReason = "confirm it's you to delete all data."
        static let reauthFailed = "couldn't confirm it's you, so nothing was deleted."
        static let continueAction = "continue"
        static let confirmWord = "delete"
        static let confirmField = "type delete"
        static let action = "delete everything"
        static let working = "deleting…"
        static let failed = "something went wrong, so nothing was deleted. try again in a moment."
        static let done = "everything has been deleted from this phone."
        static func partial(_ leftovers: [String]) -> String {
            "your journal is empty, but this couldn't be removed: \(leftovers.joined(separator: ", ")). you can run delete all data again to retry."
        }
        static let dismiss = "dismiss"

        // Names of what device-local owners wipe, used only to say what couldn't be removed.
        static let wiperPassphrase = "the backup passphrase"
        static let wiperHealthAnchor = "health sync position"
        static let wiperOnboarding = "onboarding progress"
        static let wiperReminders = "scheduled reminders"
        static let wiperDeviceFiles = "saved restore copies"
        static let wiperAutoBackup = "the automatic backup settings on this phone"
        static let leftoverOldData = "an older copy of your journal"
        static let leftoverCaches = "cached photo previews"
    }
}

extension Copy {
    /// Automatic backups to a folder the user picked (settings, backup section).
    enum AutoBackup {
        static let title = "automatic backups"
        static let off = "not set up"
        static let needsPassphrase = "backups are paused until you set a passphrase below."
        static let chooseFolder = "choose a backup folder"
        static let chooseHint = "pick a folder, ideally in icloud drive. be reyt keeps its backups inside it."
        static let backUpNow = "back up now"
        static let backingUp = "backing up…"
        static let noBackupYet = "no backup yet"
        static let uploaded = "uploaded"
        static let icloudRow = "icloud"
        static let lastBackupRow = "last backup"
        static let lastConfirmedRow = "last confirmed in icloud"
        static let waitingToUpload = "waiting to upload"
        static let pending = "changes waiting to back up"
        static let notInICloud =
            "this folder is only on this iphone, so it won't protect you if the phone is lost. pick a folder in icloud drive."
        static let cleanupPaused =
            "cleanup paused. some backups in this folder were made elsewhere, so old photo copies are being kept for now."

        static func folder(_ name: String) -> String { "folder: \(name)" }

        static func lastBackup(_ when: Date, now: Date = .now, calendar: Calendar = .current) -> String {
            let time = when.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute())
                .lowercased()
            if calendar.isDate(when, inSameDayAs: now) { return "today \(time)" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                calendar.isDate(when, inSameDayAs: yesterday)
            {
                return "yesterday \(time)"
            }
            return "\(Dates.format(when, weekday: .abbreviated, month: .abbreviated, calendar: calendar)) \(time)"
        }

        static func error(_ code: BackupErrorCode) -> String {
            switch code {
            case .folderMissing: "the backup folder couldn't be found. choose it again and backups will carry on."
            case .storageFull: "icloud is full, so backups are waiting. free some space and they'll carry on."
            case .uploadFailed: "the last backup couldn't be saved. be reyt will try again."
            case .photoUnreadable:
                "a photo couldn't be read, so the last backup didn't finish. your other days are safe."
            case .verifyFailed: "the last backup didn't check out, so it was thrown away. be reyt will try again."
            case .other: "something went wrong with the last backup. be reyt will try again."
            }
        }

        static let uploadError = "icloud couldn't upload the latest backup yet. it will keep trying."
        static let folderRow = "backup folder"
        static let upload = "upload"
    }
}
