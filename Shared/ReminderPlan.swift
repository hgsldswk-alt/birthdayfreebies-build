import Foundation

struct ReminderEvent: Equatable, Hashable, Sendable {
    enum Kind: String, Sendable { case birthday, signup, claim }

    let kind: Kind
    let due: Day
    var offerID: UUID?
    var name: String?

    var title: String {
        switch kind {
        case .birthday: return L.t("reminder.birthday")
        case .signup: return L.f("reminder.signup", name ?? "")
        case .claim: return L.f("reminder.claim", name ?? "")
        }
    }

    var alertDays: [Day] { alertDays(calendar: BirthdayDates.calendar()) }

    func alertDays(calendar: Calendar) -> [Day] {
        [due.adding(kind == .birthday ? -30 : -1, calendar: calendar), due]
    }
}

struct ScheduledReminder: Equatable, Sendable {
    let day: Day
    let fireAt: Date
    let events: [ReminderEvent]
}

enum ReminderPlan {
    static func events(state: ChecklistState, on today: Day,
                       calendar: Calendar = BirthdayDates.calendar()) -> [ReminderEvent] {
        var events: [ReminderEvent] = []
        if state.preferences.birthdayReminders, let birthday = state.preferences.birthday {
            let next = birthday.next(from: today, calendar: calendar)
            for year in next.year...(next.year + 1) {
                events.append(.init(kind: .birthday, due: birthday.inYear(year, calendar: calendar)))
            }
        }
        if state.preferences.offerReminders {
            events += state.resolved(calendar: calendar).flatMap { row -> [ReminderEvent] in
                guard row.entry.claimed == nil, !row.entry.archived,
                      row.ends.map({ $0 < today }) != true else { return [] }
                var result: [ReminderEvent] = []
                if row.needsSignup, let due = row.signupBy, due >= today {
                    result.append(.init(kind: .signup, due: due, offerID: row.id, name: row.entry.merchant.name))
                }
                if row.entry.checked, row.validWindow, let due = row.ends, due >= today {
                    result.append(.init(kind: .claim, due: due, offerID: row.id, name: row.entry.merchant.name))
                }
                return result
            }
        }
        return events.sorted {
            if $0.due != $1.due { return $0.due < $1.due }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.name != $1.name { return ($0.name ?? "") < ($1.name ?? "") }
            return ($0.offerID?.uuidString ?? "") < ($1.offerID?.uuidString ?? "")
        }
    }

    static func schedule(state: ChecklistState, now: Date,
                         calendar: Calendar = BirthdayDates.calendar(), limit: Int = 60) -> [ScheduledReminder] {
        let today = Day(now, calendar: calendar)
        var merged: [Day: [ReminderEvent]] = [:]
        for event in events(state: state, on: today, calendar: calendar) {
            for day in event.alertDays(calendar: calendar) {
                merged[day, default: []].append(event)
            }
        }
        return Array(merged.keys.sorted().compactMap { day -> ScheduledReminder? in
            guard let fireAt = day.date(in: calendar, hour: 9), fireAt > now,
                  let events = merged[day] else { return nil }
            return ScheduledReminder(day: day, fireAt: fireAt, events: events)
        }.prefix(limit))
    }
}
