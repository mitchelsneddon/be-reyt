import Foundation
import Testing

@testable import ReytKit

private func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

@Suite("DateKey")
struct DateKeyTests {
    @Test("string round trip")
    func roundTrip() throws {
        let k = try #require(DateKey("2026-11-08"))
        #expect(k.string == "2026-11-08")
        #expect(k.year == 2026 && k.month == 11 && k.day == 8)
        let data = try JSONEncoder().encode(k)
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-11-08\"")
        #expect(try JSONDecoder().decode(DateKey.self, from: data) == k)
    }

    @Test(
        "invalid strings are rejected",
        arguments: [
            "2026-02-30", "2026-13-01", "abc", "2026-00-10", "2026-01-00", "2026-1-01", "2026-01-1",
            "", "2026-01-01 ", "+026-01-01", "2026/01/01", "2025-02-29",
        ])
    func invalid(_ s: String) {
        #expect(DateKey(s) == nil)
    }

    @Test("leap day only in leap years")
    func leap() {
        #expect(DateKey("2024-02-29") != nil)
        #expect(DateKey("2100-02-29") == nil)
        #expect(DateKey("2000-02-29") != nil)
    }

    @Test("decoding a bad string throws")
    func decodeBad() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DateKey.self, from: Data("\"2026-02-30\"".utf8))
        }
    }

    @Test("same instant gives different keys in different time zones")
    func zonesDiffer() {
        // 22:30 on 5 Nov in Los Angeles (PST, UTC-8) is 06:30 on 6 Nov UTC
        let instant = ISO8601DateFormatter().date(from: "2026-11-06T06:30:00Z")!
        #expect(DateKey(date: instant, calendar: calendar("America/Los_Angeles")).string == "2026-11-05")
        #expect(DateKey(date: instant, calendar: calendar("UTC")).string == "2026-11-06")
        #expect(DateKey(date: instant, calendar: calendar("Pacific/Auckland")).string == "2026-11-06")
    }

    @Test("just before and after local midnight")
    func midnight() {
        let cal = calendar("Europe/London")
        let midnight = DateKey("2026-06-10")!.date(in: cal)
        #expect(DateKey(date: midnight.addingTimeInterval(-1), calendar: cal).string == "2026-06-09")
        #expect(DateKey(date: midnight, calendar: cal).string == "2026-06-10")
    }

    @Test(
        "date(in:) is start of day and round trips across DST days",
        arguments: [
            ("Europe/London", "2026-03-29"), ("Europe/London", "2026-10-25"),
            ("America/Edmonton", "2026-03-08"), ("America/Edmonton", "2026-11-01"),
            ("America/Los_Angeles", "2026-03-08"), ("America/Los_Angeles", "2026-11-01"),
        ])
    func dstRoundTrip(tz: String, key: String) {
        let cal = calendar(tz)
        let k = DateKey(key)!
        let start = k.date(in: cal)
        #expect(start == cal.startOfDay(for: start))
        #expect(DateKey(date: start, calendar: cal) == k)
    }

    @Test("day arithmetic is unaffected by DST")
    func dstAdding() {
        #expect(DateKey("2026-03-28")!.adding(days: 1).string == "2026-03-29")
        #expect(DateKey("2026-03-29")!.adding(days: 1).string == "2026-03-30")
        #expect(DateKey("2026-10-24")!.adding(days: 2).string == "2026-10-26")
        #expect(DateKey("2026-10-26")!.days(from: DateKey("2026-10-25")!) == 1)
        #expect(DateKey("2026-03-08")!.adding(days: 1).string == "2026-03-09")
        #expect(DateKey("2026-11-02")!.days(from: DateKey("2026-10-31")!) == 2)
    }

    @Test("epochDay across 1970")
    func epoch() {
        #expect(DateKey("1970-01-01")!.epochDay == 0)
        #expect(DateKey("1969-12-31")!.epochDay == -1)
        #expect(DateKey("1900-01-01")!.epochDay == -25_567)
        #expect(DateKey("2000-03-01")!.epochDay == 11_017)
        #expect(DateKey(epochDay: -1).string == "1969-12-31")
        #expect(DateKey(epochDay: -25_567).string == "1900-01-01")
    }

    @Test("epochDay and init(epochDay:) are inverse over a wide range")
    func inverse() {
        for e in stride(from: -800_000, through: 800_000, by: 37) {
            #expect(DateKey(epochDay: e).epochDay == e)
        }
    }

    @Test("weekday")
    func weekday() {
        #expect(DateKey("1970-01-01")!.weekday == 4)  // Thursday
        #expect(DateKey("1969-12-31")!.weekday == 3)  // Wednesday
        #expect(DateKey("2026-11-08")!.weekday == 0)  // Sunday
        #expect(DateKey("2026-11-14")!.weekday == 6)  // Saturday
    }

    @Test("adding and subtracting across month and year boundaries")
    func boundaries() {
        #expect(DateKey("2026-12-31")!.adding(days: 1).string == "2027-01-01")
        #expect(DateKey("2027-01-01")!.adding(days: -1).string == "2026-12-31")
        #expect(DateKey("2028-02-28")!.adding(days: 1).string == "2028-02-29")
        #expect(DateKey("2027-02-28")!.adding(days: 1).string == "2027-03-01")
        #expect(DateKey("1969-12-31")!.adding(days: 1).string == "1970-01-01")
        #expect(DateKey("2026-01-01")!.adding(days: -365).string == "2025-01-01")
        #expect(DateKey("2027-01-01")!.days(from: DateKey("2026-01-01")!) == 365)
    }

    @Test("ordering")
    func ordering() {
        #expect(DateKey("2026-01-31")! < DateKey("2026-02-01")!)
        #expect(DateKey("2025-12-31")! < DateKey("2026-01-01")!)
        #expect(!(DateKey("2026-02-01")! < DateKey("2026-02-01")!))
    }
}
