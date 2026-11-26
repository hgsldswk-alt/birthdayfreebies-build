import CoreImage
import Foundation
import UIKit
import XCTest

final class ChecklistTests: XCTestCase {
    private let utc = BirthdayDates.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
    private let today = Day(year: 2026, month: 12, day: 31)

    private func offer(name: String = "Maple & Rye", signup: Requirement = .no) -> OfferEntry {
        OfferEntry(year: 2026, merchant: OfferValue(name: name, gift: "Pastry"), signup: signup,
                   purchase: .no, signupBy: .fixed(today.adding(-1, calendar: utc)),
                   opens: .fixed(today), ends: .fixed(today.adding(1, calendar: utc)), checked: true)
    }

    func testWindowIncludesBothEndsAndExpiresNextLocalDay() {
        let row = offer().resolved(birthday: nil, calendar: utc)
        XCTAssertEqual(row.stage(on: today.adding(-1, calendar: utc)), .waiting)
        XCTAssertEqual(row.stage(on: today), .ready)
        XCTAssertEqual(row.stage(on: Day(year: 2027, month: 1, day: 1)), .ready)
        XCTAssertEqual(row.stage(on: Day(year: 2027, month: 1, day: 2)), .past)
    }

    func testSignupUnknownLateSignupUncheckedAndMissingDates() {
        var row = offer(signup: .unknown)
        XCTAssertEqual(row.resolved(birthday: nil).stage(on: today), .signup)
        row.signedUp = true
        XCTAssertEqual(row.resolved(birthday: nil).stage(on: today), .ready)
        row.checked = false
        XCTAssertEqual(row.resolved(birthday: nil).stage(on: today), .waiting)
        row.checked = true
        row.ends = nil
        XCTAssertEqual(row.resolved(birthday: nil).stage(on: today), .waiting)
    }

    func testLeapDayAndCalendarTimeZone() throws {
        let birthday = Birthday(month: 2, day: 29)
        XCTAssertEqual(birthday.inYear(2027, calendar: utc), Day(year: 2027, month: 2, day: 28))
        XCTAssertEqual(birthday.inYear(2028, calendar: utc), Day(year: 2028, month: 2, day: 29))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-01T04:00:00Z"))
        let west = BirthdayDates.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let east = BirthdayDates.calendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(Day(instant, calendar: west), today)
        XCTAssertEqual(Day(instant, calendar: east), today.adding(1, calendar: utc))
    }

    func testStableSortAndDatesWithoutDeadlineLast() {
        let first = offer(name: "First")
        var second = offer(name: "Second")
        second.ends = .fixed(today.adding(10, calendar: utc))
        var unknown = offer(name: "No date")
        unknown.opens = nil
        unknown.ends = nil
        let rows = [unknown, second, first].map { $0.resolved(birthday: nil) }
        XCTAssertEqual(ResolvedOffer.sorted(rows, on: today).map(\.id), [first.id, second.id, unknown.id])
    }

    func testBackfillClaimIsIdempotentAndCanBeUndone() {
        let row = offer()
        let expired = today.adding(2, calendar: utc)
        var state = ChecklistState()
        state.add([row], in: row.year)
        XCTAssertFalse(state.claim(row.id, day: expired, on: expired))
        XCTAssertTrue(state.claim(row.id, day: today, on: expired, backfill: true))
        XCTAssertFalse(state.claim(row.id, day: today, on: expired, backfill: true))
        XCTAssertEqual(state.claimCount(in: row.year), 1)
        XCTAssertEqual(state.cycles[row.year]?.milestones, [1])
        XCTAssertEqual(state.entries.first?.confirmedFree, true)
        state.update(row.id) { $0.claimed = nil }
        XCTAssertEqual(state.claimCount(in: row.year), 0)
        XCTAssertEqual(state.cycles[row.year]?.milestones, [1])
    }

    func testReusePreservesHistoryAndRelativeDatesAndKeepsCrossYearOffersVisible() throws {
        var state = ChecklistState()
        state.preferences.birthday = Birthday(month: 12, day: 31)
        var row = offer(signup: .yes)
        row.signupBy = .relative(-7)
        row.signedUp = true
        row.notes = "Show member ID"
        state.add([row], in: 2026)
        XCTAssertFalse(state.shouldReuse(on: today))
        XCTAssertEqual(state.reuse(from: 2026, on: today), 2027)
        let reused = try XCTUnwrap(state.rows(in: 2027).first)
        XCTAssertEqual(reused.signupBy, .relative(-7))
        XCTAssertNil(reused.opens)
        XCTAssertNil(reused.ends)
        XCTAssertEqual(reused.priorSignupYear, 2026)
        XCTAssertEqual(reused.notes, row.notes)
        XCTAssertFalse(reused.checked)
        XCTAssertFalse(reused.signedUp)
        XCTAssertEqual(state.reuse(from: 2026, on: today), 2027)
        XCTAssertEqual(state.rows(in: 2027).map(\.id), [reused.id])
        XCTAssertEqual(state.rows(in: 2026), [row])
        XCTAssertTrue(state.currentRows(on: today.adding(1, calendar: utc)).contains { $0.id == row.id })
        XCTAssertFalse(state.currentRows(on: today.adding(2, calendar: utc)).contains { $0.id == row.id })
    }

    func testRemindersMergeAtNineAndRespectEligibility() throws {
        let now = try XCTUnwrap(today.date(in: utc, hour: 8))
        var state = ChecklistState()
        state.preferences.birthday = Birthday(month: 12, day: 31)
        state.preferences.birthdayReminders = true
        state.preferences.offerReminders = true
        var row = offer(signup: .yes)
        row.signupBy = .fixed(today)
        state.add([row], in: row.year)
        let plan = ReminderPlan.schedule(state: state, now: now, calendar: utc)
        let sameDay = try XCTUnwrap(plan.first)
        XCTAssertEqual(sameDay.day, today)
        XCTAssertEqual(utc.component(.hour, from: sameDay.fireAt), 9)
        XCTAssertEqual(Set(sameDay.events.map(\.kind)), [.birthday, .signup, .claim])
        let afterNine = try XCTUnwrap(today.date(in: utc, hour: 10))
        XCTAssertFalse(ReminderPlan.schedule(state: state, now: afterNine, calendar: utc).contains { $0.day == today })
        state.update(row.id) { $0.signedUp = true; $0.checked = false }
        XCTAssertEqual(ReminderPlan.schedule(state: state, now: now, calendar: utc).first?.events.map(\.kind), [.birthday])
        XCTAssertEqual(ReminderPlan.schedule(state: state, now: now, calendar: utc, limit: 1).count, 1)
    }

    func testCodeRoundTripDropsPrivateAndAbsoluteFieldsAndProtectsLocalRows() throws {
        var row = offer()
        row.signupBy = .relative(-7)
        row.merchant.location = "private address"
        row.notes = "secret code"
        row.claimed = today
        let code = try ShareCode.encode([row])
        XCTAssertTrue(code.hasPrefix("BFC1:"))
        let decoded = try ShareCode.decode(code)
        let received = try XCTUnwrap(decoded.first).entry(in: 2027)
        XCTAssertEqual(received.signupBy, .relative(-7))
        XCTAssertNil(received.opens)
        XCTAssertNil(received.claimed)
        XCTAssertTrue(received.notes.isEmpty)
        XCTAssertTrue(received.merchant.location.isEmpty)
        XCTAssertFalse(received.checked)
        XCTAssertEqual(ShareCode.preview(decoded, existing: [row]).first?.conflict, .existing)
        XCTAssertTrue(ShareCode.preview(decoded + decoded, existing: []).allSatisfy { $0.conflict == .ambiguous })
        var state = ChecklistState()
        XCTAssertEqual(state.add([received], in: 2027, portable: true).count, 1)
        XCTAssertTrue(state.add([received], in: 2027, portable: true).isEmpty)
    }

    func testInvalidAndOversizeCodes() throws {
        for code in ["", "BFC0:AAAA", "BFC1:A", "BFC1:AAAA=", "BFC1:" + String(repeating: "x", count: 8192)] {
            XCTAssertThrowsError(try ShareCode.decode(code))
        }
        func packed(_ json: String) -> String {
            "BFC1:" + Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        XCTAssertThrowsError(try ShareCode.decode(packed(#"{"v":1,"offers":[{"name":"A","gift":"","signup":"no","endsOffset":367}]}"#)))
        XCTAssertThrowsError(try ShareCode.decode(packed(#"{"v":1,"offers":[{"name":"A","gift":"","signup":false}]}"#)))
        XCTAssertThrowsError(try ShareCode.encode(Array(repeating: offer(), count: 51)))
    }

    func testWidgetUpdatesAtDayBoundaryAndLinksDecode() {
        let row = offer()
        var state = ChecklistState()
        state.add([row], in: row.year)
        let data = WidgetSnapshot.make(from: state, on: today)
        XCTAssertEqual(data.readyCount(on: today.adding(-1, calendar: utc)), 0)
        XCTAssertEqual(data.readyCount(on: today), 1)
        XCTAssertEqual(data.nextDue(on: today)?.id, row.id)
        let nextDay = today.adding(2, calendar: utc)
        XCTAssertEqual(data.readyCount(on: nextDay), 0)
        XCTAssertNil(data.nextDue(on: nextDay))
        for link in [AppLink.home, .birthday, .create, .offer(row.id), .due(today)] {
            XCTAssertEqual(AppLink(url: link.url), link)
        }
        XCTAssertNil(AppLink(url: URL(string: "birthdayfreebies://due/20260230")!))
    }

    func testReviewRequiresThreeClaimsThreeDaysAndAnotherCoreAction() {
        var state = ChecklistState()
        state.select(2026)
        for index in 1...3 {
            var row = offer(name: String(index))
            row.claimed = today
            state.add([row], in: 2026)
        }
        state.recordUse(on: today, year: 2026, version: "1")
        state.recordUse(on: today, year: 2026, version: "1")
        state.recordUse(on: today.adding(-1), year: 2026, version: "1")
        XCTAssertFalse(state.preferences.reviewPending)
        state.recordUse(on: today.adding(-2), year: 2026, version: "1")
        XCTAssertTrue(state.preferences.reviewPending)
        state.preferences.reviewPending = false
        state.preferences.reviewedVersion = "1"
        state.recordUse(on: today, year: 2026, version: "1")
        XCTAssertFalse(state.preferences.reviewPending)
    }

    func testPaidDownloadIncludesEveryFeature() {
        XCTAssertTrue(Launch.freePeriod)
        XCTAssertFalse(Launch.testing)
        XCTAssertNotEqual(L.t("app.title"), "app.title")
        XCTAssertNil(ShareImage.downloadURL(appID: ""))
    }

    func testSwiftDataSaveUpdateAndRemove() async throws {
        let ledger = try await Task.detached { try Ledger.open(inMemory: true) }.value
        let blank = try await ledger.load()
        var state = blank
        let row = offer()
        state.add([row], in: row.year)
        try await ledger.save(state, replacing: blank)
        let first = try await ledger.load()
        XCTAssertEqual(first, state)
        state.update(row.id) { $0.claimed = today }
        try await ledger.save(state, replacing: first)
        let second = try await ledger.load()
        XCTAssertEqual(second, state)
        state.entries.removeAll()
        try await ledger.save(state, replacing: second)
        let third = try await ledger.load()
        XCTAssertEqual(third, state)
    }

    @MainActor func testShareImageDimensionsAndQRCode() throws {
        let url = try XCTUnwrap(ShareImage.downloadURL(appID: "1234567890"))
        let png = try XCTUnwrap(ShareImage.png(.stats(claimed: 12, free: 8), url: url))
        let cgImage = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        let reader = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = reader.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(messages, [url.absoluteString])
    }
}
