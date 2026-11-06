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

    enum History {
        static let modeLabel = "history view"
        static let calendar = "calendar"
        static let list = "list"
        static let emptyJournal = "nothing here yet. today is a good place to start."
        static let noMatches = "nothing matches that."
        static let searchPrompt = "search your days"
        static let tagFilterLabel = "filter by tag"
        static let calendarLabel = "calendar of your days"
        static let loadFailed = "couldn't open your history. tap to try again."
        static let hasEntry = "has an entry"
        static let photosUnit = "photos"
        static let moodsUnit = "moods"

        /// "november 2026", lowercase.
        static func monthHeader(year: Int, month: Int, calendar: Calendar = .current) -> String {
            guard let key = DateKey(year: year, month: month, day: 1) else { return "" }
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
            return key.date(in: calendar).formatted(style).lowercased()
        }

        /// "wed 4 nov", lowercase.
        static func rowDate(_ key: DateKey, calendar: Calendar = .current) -> String {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
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

    enum Reviews {
        static let title = "reviews"
        static let thisWeeksReview = "this week's review"
        static let loadFailed = "couldn't open your reviews. tap to try again."
        static let weekdayShort = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

        static func weekOf(_ range: String) -> String { "week of \(range)" }
        static func coverage(_ recorded: Int) -> String { "\(recorded) of 7 days recorded" }
        static func rowLabel(week: String, coverage: String, isLatest: Bool) -> String {
            isLatest ? "\(thisWeeksReview), \(week), \(coverage)" : "\(week), \(coverage)"
        }

        /// "your first review opens on sunday 8 nov."
        static func emptyList(opensOn key: DateKey, calendar: Calendar = .current) -> String {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).day().month(.abbreviated)
            return "your first review opens on \(key.date(in: calendar).formatted(style).lowercased())."
        }

        static let emptyWeek = "nothing was written this week."

        static let scoresTitle = "day scores"
        static func average(_ display: String, scoredDays: Int) -> String {
            "\(display) average across \(scoredDays) scored \(scoredDays == 1 ? "day" : "days")"
        }
        static let noScores = "no day scores this week."
        static let chartLabel = "day scores, sunday to saturday"
        static func pointLabel(date: String, score: DayScore) -> String { "\(date), \(score.label)" }
        static func chartSummary(scoredDays: Int) -> String {
            "day scores for \(scoredDays) of 7 days. days without a score are left blank."
        }

        static let moodsTitle = "moods"
        static let noMoods = "no moods recorded this week."
        static func moodRow(label: String, count: Int, of days: Int) -> String {
            "\(label) · \(count) of \(days) mood-logged \(days == 1 ? "day" : "days")"
        }

        static let comparisonTitle = "compared with last week"
        static func comparisonScore(average: String, days: Int, lastAverage: String, lastDays: Int) -> String {
            "average \(average) across \(days) days, last week \(lastAverage) across \(lastDays)"
        }
        static func comparisonMood(label: String, count: Int, of days: Int, lastCount: Int, lastOf: Int) -> String {
            "\(label) on \(count) of \(days) days, last week \(lastCount) of \(lastOf)"
        }

        static func highestTitle(count: Int) -> String { count == 1 ? "highest-scored day" : "highest-scored days" }
        static func lowestTitle(count: Int) -> String { count == 1 ? "lowest-scored day" : "lowest-scored days" }
        static let openDayHint = "opens that day"

        static func workoutSummary(count: Int, duration: String) -> String {
            "\(count) \(count == 1 ? "workout" : "workouts"), \(duration) in all"
        }
        static func distanceLine(distance: String, kind: WorkoutActivity.DistanceKind) -> String {
            switch kind {
            case .walkingRunning: "\(distance) walking and running"
            case .cycling: "\(distance) cycling"
            case .swimming: "\(distance) swimming"
            }
        }

        static let moreOfThisQuestion = "what would you like a little more of next week?"
        static let moreOfThisHelper = "time outdoors, seeing friends, rest, anything you choose."
        static let moreOfThisLabel = "answer to what would you like a little more of next week"
        static func moreOfThisTarget(_ range: String) -> String { "for \(range)" }
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

    enum Plan {
        static let question = "what’s one thing you want or need to do next week?"
        static let helper =
            "something you’re looking forward to, a goal, a task, or something you’d like to achieve."
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
        static let thisWeekTitle = "your plan for this week"
        static func rangeTitle(_ range: String) -> String { "your plan for \(range)" }
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
        static let recentTitle = "recent"
        static let addPlaceholder = "add a tag"
        static let addLabel = "add tag"
        static let addFailed = "couldn't add that tag. try again in a moment."
        static func chipLabel(_ name: String, selected: Bool) -> String {
            selected ? "\(name), on this day" : "\(name), not on this day"
        }
    }

    enum Photos {
        static let title = "photos"
        static let add = "add photos"
        static let addHint = "choose photos from your library"
        static func thumbnailLabel(_ index: Int, of count: Int) -> String { "photo \(index) of \(count)" }
        static let thumbnailHint = "opens the photo full screen"
        static let viewerLabel = "photo"
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
        static let section = "health"
        static let unavailable = "health isn't available on this device."
        static let notAsked = "be reyt hasn't asked to read your workouts yet."
        static let asked = "be reyt has asked to read your workouts."
        static let allow = "allow access to workouts"
        static let allowHint = "shows the iOS health permission sheet"
        static let guidance =
            "ios doesn't tell apps if read access was denied, so be reyt can't see it either. if workouts don't appear, check settings › privacy & security › health › be reyt."
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
        static let allowHint = "shows the iOS notification permission sheet"
        static let denied = "notifications are off for be reyt, so the reminder can't show."
        static let openSettings = "open ios settings"
        static let openSettingsHint = "opens the notification settings for be reyt"
        static let footer =
            "reminders are scheduled ahead for 4 weeks and refresh whenever you open be reyt. if you don't open it for 4 weeks, they stop. a reminder is skipped on days you've already written something. focus modes and notification summaries can delay or hide it. nothing from your journal appears in the notification."
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
        static let generating = "writing your reflection on this phone…"
        static let regenerate = "regenerate"
        static let regenerateHint = "writes the reflection again with the newer wording"
        static let tryAgain = "try again"
        static let footnote = "written on this phone by apple's on-device model. it can get things wrong."
        static let purged = "this week changed, so the reflection was cleared."
        static let highlights = "highlights"
        static let difficult = "what felt difficult"
        static let themes = "recurring themes"
        static let questions = "to sit with"
        static let intro = "a short reflection, written only on this phone. nothing is sent anywhere."
        static func datesLabel(_ dates: [String]) -> String { "days: " + dates.joined(separator: ", ") }

        static func failure(_ failure: ReflectionFailure) -> String {
            switch failure {
            case .deviceNotEligible:
                "this iphone can't run apple's on-device model, so there's no written reflection. your numbers are below."
            case .appleIntelligenceNotEnabled:
                "turn on apple intelligence in settings to write a reflection. your numbers are below."
            case .modelNotReady:
                "the on-device model is still downloading. try again in a little while. your numbers are below."
            case .unsupportedLanguage:
                "the on-device model doesn't support this language yet, so there's no written reflection. your numbers are below."
            case .guardrail:
                "the on-device model couldn't write a reflection for this week. your numbers are below."
            case .refused:
                "the on-device model chose not to write about this week. your numbers are below."
            case .tooLong:
                "this week has more writing than the on-device model can read at once, so there's no reflection. your numbers are below."
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
        static let aiFooter =
            "reflections are written by apple's on-device model, on this phone. your journal is never sent anywhere."
        static let backupSection = "backup"
        static let passphraseRow = "backup passphrase"
        static let passphraseSet = "set"
        static let passphraseNotSet = "not set yet"
        static let exportRow = "export a backup"
        static let exportRowNeedsPassphrase = "set a passphrase first"
        static let restoreRow = "restore from a file"
        static let undoRow = "undo last restore"
        static let undoHint = "goes back to what was on this phone before the last restore"
        static let backupFooter =
            "backups are encrypted with your passphrase and stay in the place you choose. nothing leaves your phone on its own."
    }

    enum Passphrase {
        static let setTitle = "backup passphrase"
        static let changeTitle = "change passphrase"
        static let warning =
            "write this down somewhere safe. without it, your backups can't be opened, not even by us."
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

        static func warningLine(_ code: String, count: Int) -> String? {
            code == ArchiveWarning.missingAttachment ? Export.skipped(count) : nil
        }

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
                "couldn't save a safety copy of what's here, so nothing was changed. try again in a moment."
            case .switchFailed: "something went wrong, so nothing was changed. try again in a moment."
            case .busy: "a restore is already running."
            case .nothingToUndo: "there's nothing to go back to."
            }
        }
    }

    enum ReadableExport {
        static let row = "readable exports"
        static let rowHint = "make a markdown or pdf copy of your journal that you can read anywhere"
        static let title = "readable exports"
        static let markdownRow = "export as markdown"
        static let pdfRow = "export as pdf"
        static let notEncrypted = "readable exports aren't encrypted. keep them somewhere private."
        static let footer =
            "these are for reading, not for restoring. use a backup if you want to bring your journal back into be reyt."
        static let rangeSection = "which days"
        static let rangeLabel = "days to include"
        static let rangeAll = "all days"
        static let rangeCustom = "pick dates"
        static let startLabel = "from"
        static let endLabel = "to"
        static let workoutsToggle = "include workouts"
        static let workoutsFooter =
            "workouts are copied from apple health. when this is off, they are left out of the export and it says so."
        static let working = "putting it together…"
        static let saved = "export saved. it isn't encrypted, so keep it somewhere private."
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
        static let sectionFooter =
            "unzip the export in files first, then choose the folder. everything is read on this phone, nothing is sent anywhere."
        static let title = "import from apple journal"
        static let close = "close"
        static let cancel = "cancel"
        static let importAction = "import"
        static let done = "done"
        static let tryAgain = "choose another folder"
        static let readingTitle = "reading your export…"
        static func progress(done: Int, total: Int) -> String { "\(done) of \(total) entries" }
        static let importingTitle = "adding to your journal…"
        static let noTimes = "the export has no times, so only dates and titles are kept."
        static let nothingNew = "nothing new to import."
        static let nothingNewDetail = "every entry in this export is already in your journal."
        static func entries(_ n: Int) -> String { n == 1 ? "1 entry" : "\(n) entries" }
        static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        static func photos(_ n: Int) -> String { n == 1 ? "1 photo" : "\(n) photos" }
        static func summary(entries: Int, days: Int, photos: Int) -> String {
            photos == 0
                ? "\(Self.entries(entries)) on \(Self.days(days))"
                : "\(Self.entries(entries)) on \(Self.days(days)), \(Self.photos(photos))"
        }
        static let willImportSection = "will be added"
        static let alreadyImportedSection = "already imported"
        static func alreadyImported(_ n: Int) -> String {
            n == 1
                ? "1 entry is already in your journal and will be skipped."
                : "\(n) entries are already in your journal and will be skipped."
        }
        static let unsupportedSection = "left out"
        static let unsupportedFooter = "these can't be brought in, the rest of the entry still can."
        static let fallbackNote =
            "some entries had no readable date, so the date in the file name was used (one day earlier, as the export names files)."
        static let conflictsSection = "days that already have writing"
        static let conflictsFooter = "add puts the imported text after what you wrote. skip leaves that day alone."
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
        static let failuresFooter = "these files were left alone. nothing already in your journal was changed."
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
        static let busy = "an import is already running."
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
            "backup files you've saved, or that were saved to your backup folder. delete those yourself in the files app.",
            "apple health data. be reyt only ever reads it, and never changes it.",
        ]
        static let irreversible = "this can't be undone. be reyt will be empty, as if you'd just installed it."
        static let reauthReason = "confirm it's you to delete all data."
        static let reauthFailed = "couldn't confirm it's you, so nothing was deleted."
        static let continueAction = "continue"
        static let confirmPrompt = "type delete to confirm."
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
        static let chooseFolder = "choose a backup folder"
        static let chooseAnother = "choose a different folder"
        static let chooseHint = "pick a folder, ideally in icloud drive. be reyt keeps its backups inside it."
        static let backUpNow = "back up now"
        static let backingUp = "backing up…"
        static let noBackupYet = "no backup yet"
        static let uploaded = "uploaded to icloud"
        static let waitingToUpload = "waiting to upload"
        static let pending = "changes waiting to back up"
        static let notInICloud =
            "this folder is only on this iphone, so it won't protect you if the phone is lost. pick a folder in icloud drive."
        static let cleanupPaused =
            "cleanup paused. some backups in this folder were made elsewhere, so old photo copies are being kept for now."
        static let needsPassphrase = "set a backup passphrase above to start backing up."
        static let needsFolder = "choose a folder and be reyt will back up automatically while it's open."
        static let footer =
            "backups run while be reyt is open, after a quiet minute. each day keeps one backup, and the latest 30 are kept."

        static func folder(_ name: String) -> String { "folder: \(name)" }

        static func lastBackup(_ when: Date, now: Date = .now, calendar: Calendar = .current) -> String {
            let time = when.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute())
                .lowercased()
            if calendar.isDate(when, inSameDayAs: now) { return "last backup: today \(time)" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                calendar.isDate(when, inSameDayAs: yesterday)
            {
                return "last backup: yesterday \(time)"
            }
            let day = when.formatted(
                Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(
                    .abbreviated))
            return "last backup: \(day.lowercased()) \(time)"
        }

        static func lastConfirmed(_ when: Date, now: Date = .now, calendar: Calendar = .current) -> String {
            lastBackup(when, now: now, calendar: calendar).replacingOccurrences(
                of: "last backup:", with: "last confirmed in icloud:")
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
