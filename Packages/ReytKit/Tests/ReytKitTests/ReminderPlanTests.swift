import Foundation
import SwiftData
import Testing

@testable import ReytKit

private func day(_ s: String) -> DateKey { DateKey(s)! }

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

/// `s` ("2026-11-05 20:59") as an instant in `zone`.
private func instant(_ s: String, in zone: String) -> Date {
    let f = DateFormatter()
    f.calendar = calendar(zone)
    f.timeZone = TimeZone(identifier: zone)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func plan(
    _ now: String, zone: String = "Europe/London", content: Set<DateKey> = [], enabled: Bool = true,
    horizon: Int = 28
) -> [DateKey] {
    let cal = calendar(zone)
    let at = instant(now, in: zone)
    return ReminderPlan.dates(
        today: DateKey(date: at, calendar: cal), now: at, calendar: cal, hour: 21, horizonDays: horizon,
        contentDays: content, enabled: enabled)
}

@Suite("Reminder plan")
struct ReminderPlanTests {
    @Test("before 21:00 with nothing written: today through today+27")
    func beforeReminder() {
        let dates = plan("2026-11-05 20:59")
        #expect(dates.count == 28)
        #expect(dates.first == day("2026-11-05"))
        #expect(dates.last == day("2026-12-02"))
    }

    @Test("at or after 21:00 today is excluded, the next 27 remain")
    func afterReminder() {
        for now in ["2026-11-05 21:00", "2026-11-05 23:59"] {
            let dates = plan(now)
            #expect(dates.first == day("2026-11-06"))
            #expect(dates.count == 27)
            #expect(dates.last == day("2026-12-02"))
        }
    }

    @Test("today with content is excluded even before 21:00")
    func todayHasContent() {
        let dates = plan("2026-11-05 09:00", content: [day("2026-11-05")])
        #expect(dates.first == day("2026-11-06"))
        #expect(dates.count == 27)
    }

    @Test("content removed again before 21:00 brings today back")
    func contentRemoved() {
        #expect(plan("2026-11-05 20:00", content: []).first == day("2026-11-05"))
    }

    @Test("editing another day does not change today's inclusion")
    func otherDays() {
        let dates = plan("2026-11-05 09:00", content: [day("2026-11-04")])
        #expect(dates.first == day("2026-11-05"))
        #expect(dates.count == 28)
    }

    @Test("future days with content are skipped, past days outside the window are ignored")
    func futureContent() {
        let dates = plan("2026-11-05 09:00", content: [day("2026-11-07"), day("2026-11-20"), day("2025-01-01")])
        #expect(!dates.contains(day("2026-11-07")))
        #expect(!dates.contains(day("2026-11-20")))
        #expect(dates.count == 26)
    }

    @Test("disabled schedules nothing")
    func disabled() {
        #expect(plan("2026-11-05 09:00", enabled: false).isEmpty)
    }

    @Test("horizon is exactly the requested number of consecutive days")
    func horizon() {
        let dates = plan("2026-02-20 09:00", horizon: 10)
        #expect(dates == (0..<10).map { day("2026-02-20").adding(days: $0) })
        #expect(dates.last == day("2026-03-01"))
    }

    @Test("the same instant is a different today, and a different inclusion, in two zones")
    func timeZoneShift() {
        // 2026-11-05 20:30 in London is already 2026-11-06 05:30 in Tokyo.
        let london = calendar("Europe/London")
        let tokyo = calendar("Asia/Tokyo")
        let at = instant("2026-11-05 20:30", in: "Europe/London")
        func dates(_ cal: Calendar) -> [DateKey] {
            ReminderPlan.dates(
                today: DateKey(date: at, calendar: cal), now: at, calendar: cal, hour: 21, contentDays: [],
                enabled: true)
        }
        #expect(dates(london).first == day("2026-11-05"))
        #expect(dates(tokyo).first == day("2026-11-06"))
        #expect(dates(tokyo).count == 28)
    }

    @Test("identifier round trips and rejects foreign or malformed ids")
    func identifiers() {
        let key = day("2026-11-05")
        #expect(ReminderPlan.identifier(for: key) == "reminder-2026-11-05")
        #expect(ReminderPlan.parse(identifier: ReminderPlan.identifier(for: key)) == key)
        #expect(ReminderPlan.parse(identifier: "other-2026-11-05") == nil)
        #expect(ReminderPlan.parse(identifier: "reminder-2026-13-05") == nil)
        #expect(ReminderPlan.parse(identifier: "reminder-") == nil)
    }

    @Test("diff adds the missing, removes the stale, and ignores foreign identifiers")
    func diffTouchesOnlyOurs() {
        let desired = [day("2026-11-06"), day("2026-11-07")]
        let pending: Set<String> = ["reminder-2026-11-07", "reminder-2026-11-05", "reminder-junk", "backup-2026-11-05"]
        let result = ReminderPlan.diff(pending: pending, desired: desired)
        #expect(result.add == [day("2026-11-06")])
        #expect(result.remove == ["reminder-2026-11-05", "reminder-junk"])
    }

    @Test("applying a diff twice changes nothing the second time")
    func diffIdempotent() {
        let desired = (0..<5).map { day("2026-11-05").adding(days: $0) }
        let first = ReminderPlan.diff(pending: ["reminder-2026-10-01", "x"], desired: desired)
        var pending: Set<String> = ["reminder-2026-10-01", "x"]
        pending.subtract(first.remove)
        pending.formUnion(first.add.map(ReminderPlan.identifier(for:)))
        let second = ReminderPlan.diff(pending: pending, desired: desired)
        #expect(second.add.isEmpty)
        #expect(second.remove.isEmpty)
        #expect(pending.contains("x"))
    }

    @Test("a disabled plan removes every pending reminder but nothing else")
    func disabledClearsOurs() {
        let result = ReminderPlan.diff(pending: ["reminder-2026-11-05", "other"], desired: [])
        #expect(result.remove == ["reminder-2026-11-05"])
        #expect(result.add.isEmpty)
    }
}

@Suite("Reminder store")
struct ReminderStoreTests {
    private func makeStore() throws -> JournalStore {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return JournalStore(modelContainer: container, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test("settings default to on at 21, persist, and clamp the hour")
    func settingsRoundTrip() async throws {
        let store = try makeStore()
        #expect(try await store.reminderSettings() == ReminderSettings(enabled: true, hour: 21))
        let effect = try await store.updateReminderSettings(enabled: false, hour: 30)
        #expect(effect.dirty)
        #expect(try await store.reminderSettings() == ReminderSettings(enabled: false, hour: 23))
        #expect(try await store.updateReminderSettings(enabled: false, hour: 23).isEmpty)
    }

    @Test("contentDays reports only days with user content inside the range")
    func contentDaysRange() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-11-05"), .text("hello"))
        _ = try await store.updateEntry(day("2026-11-07"), .score(.good))
        _ = try await store.updateEntry(day("2026-11-20"), .text("later"))
        _ = try await store.updateEntry(day("2026-11-06"), .text("   "))
        let found = try await store.contentDays(from: day("2026-11-05"), through: day("2026-11-10"))
        #expect(found == [day("2026-11-05"), day("2026-11-07")])
    }
}
