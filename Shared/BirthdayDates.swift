import Foundation

struct Day: Codable, Hashable, Comparable, Sendable {
    let raw: Int

    init(year: Int, month: Int, day: Int) {
        raw = year * 10_000 + month * 100 + day
    }

    init(_ date: Date, calendar: Calendar = BirthdayDates.calendar()) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    var year: Int { raw / 10_000 }
    var month: Int { raw / 100 % 100 }
    var day: Int { raw % 100 }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }

    func date(in calendar: Calendar, hour: Int = 12) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    func adding(_ days: Int, calendar: Calendar = BirthdayDates.calendar()) -> Self {
        guard let date = date(in: calendar),
              let result = calendar.date(byAdding: .day, value: days, to: date) else { return self }
        return Self(result, calendar: calendar)
    }

    func days(until other: Self, calendar: Calendar = BirthdayDates.calendar()) -> Int {
        guard let first = date(in: calendar), let last = other.date(in: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                       to: calendar.startOfDay(for: last)).day ?? 0
    }

    func label(_ style: Date.FormatStyle = .dateTime.month(.abbreviated).day(),
               calendar: Calendar = BirthdayDates.calendar()) -> String {
        guard let value = date(in: calendar) else { return L.t("date.unknown") }
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return value.formatted(style)
    }
}

struct Birthday: Codable, Equatable, Sendable {
    var month: Int
    var day: Int

    func inYear(_ year: Int, calendar: Calendar = BirthdayDates.calendar()) -> Day {
        let date = Day(year: year, month: month, day: day)
        if month == 2 && day == 29, let candidate = date.date(in: calendar),
           calendar.component(.month, from: candidate) != 2 {
            return Day(year: year, month: 2, day: 28)
        }
        return date
    }

    func next(from today: Day, calendar: Calendar = BirthdayDates.calendar()) -> Day {
        let thisYear = inYear(today.year, calendar: calendar)
        return thisYear < today ? inYear(today.year + 1, calendar: calendar) : thisYear
    }
}

enum BirthdayDates {
    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

enum AppLink: Equatable, Sendable {
    case home, birthday, create, offer(UUID), due(Day)

    init?(url: URL) {
        guard url.scheme == "birthdayfreebies" else { return nil }
        switch url.host {
        case "home": self = .home
        case "birthday": self = .birthday
        case "create": self = .create
        case "offer":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .offer(id)
        case "due":
            guard let value = Int(url.lastPathComponent), (19000101...99991231).contains(value) else { return nil }
            let day = Day(year: value / 10000, month: value / 100 % 100, day: value % 100)
            let calendar = BirthdayDates.calendar()
            guard let date = day.date(in: calendar), Day(date, calendar: calendar) == day else { return nil }
            self = .due(day)
        default: return nil
        }
    }

    var url: URL {
        let path: String
        switch self {
        case .home: path = "home"
        case .birthday: path = "birthday"
        case .create: path = "create"
        case .offer(let id): path = "offer/\(id.uuidString)"
        case .due(let date): path = "due/\(date.raw)"
        }
        return URL(string: "birthdayfreebies://\(path)")!
    }
}
