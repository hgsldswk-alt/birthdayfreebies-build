import Foundation

enum Requirement: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, no, yes
    var id: Self { self }
    var title: String { L.t("requirement." + rawValue) }
}

enum OfferStage: String, CaseIterable, Sendable {
    case signup, waiting, ready, claimed, past
    var title: String { L.t("stage." + rawValue) }
}

enum DateRule: Codable, Equatable, Sendable {
    case fixed(Day)
    case relative(Int)

    func resolve(birthday: Birthday?, year: Int, calendar: Calendar) -> Day? {
        switch self {
        case .fixed(let date): return date
        case .relative(let days):
            return birthday?.inYear(year, calendar: calendar).adding(days, calendar: calendar)
        }
    }

    var offset: Int? {
        if case .relative(let value) = self { return value }
        return nil
    }

    var reusable: Self? { offset.map { .relative($0) } }
}

struct OfferValue: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var gift = ""
    var location = ""

    var portableKey: OfferKey { OfferKey(name: name, gift: gift, location: "") }
    var key: OfferKey { OfferKey(name: name, gift: gift, location: location) }
}

struct OfferKey: Hashable {
    let name: String
    let gift: String
    let location: String

    init(name: String, gift: String, location: String) {
        self.name = Self.normalize(name)
        self.gift = Self.normalize(gift)
        self.location = Self.normalize(location)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct OfferEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var year: Int
    var merchant: OfferValue
    var starterID: String?
    var signup: Requirement = .unknown
    var purchase: Requirement = .unknown
    var notes = ""
    var signupBy: DateRule?
    var opens: DateRule?
    var ends: DateRule?
    var signedUp = false
    var checked = false
    var claimed: Day?
    var priorSignupYear: Int?
    var archived = false

    func resolved(birthday: Birthday?, calendar: Calendar = BirthdayDates.calendar()) -> ResolvedOffer {
        ResolvedOffer(entry: self,
                      signupBy: signupBy?.resolve(birthday: birthday, year: year, calendar: calendar),
                      opens: opens?.resolve(birthday: birthday, year: year, calendar: calendar),
                      ends: ends?.resolve(birthday: birthday, year: year, calendar: calendar))
    }

    func reused(in year: Int) -> Self {
        var result = self
        result.id = UUID()
        result.priorSignupYear = signedUp ? self.year : priorSignupYear
        result.year = year
        result.signupBy = signupBy?.reusable
        result.opens = opens?.reusable
        result.ends = ends?.reusable
        result.signedUp = false
        result.checked = false
        result.claimed = nil
        result.archived = false
        return result
    }

    var confirmedFree: Bool { claimed != nil && checked && purchase == .no }
}

struct ResolvedOffer: Identifiable, Equatable, Sendable {
    let entry: OfferEntry
    let signupBy: Day?
    let opens: Day?
    let ends: Day?

    var id: UUID { entry.id }
    var needsSignup: Bool { !entry.signedUp && entry.signup != .no }
    var validWindow: Bool {
        guard let opens, let ends else { return false }
        return opens <= ends
    }

    func stage(on today: Day) -> OfferStage {
        if entry.claimed != nil { return .claimed }
        if entry.archived || ends.map({ $0 < today }) == true { return .past }
        if needsSignup { return .signup }
        if entry.checked, validWindow, let opens, opens <= today { return .ready }
        return .waiting
    }

    func status(on today: Day) -> String {
        switch stage(on: today) {
        case .signup:
            if let signupBy, signupBy < today { return L.t("status.missed") }
            return L.t(entry.signup == .unknown ? "status.check_signup" : "status.join")
        case .waiting:
            if !entry.checked || !validWindow { return L.t("status.verify") }
            if let opens, opens > today { return L.t("status.waiting") }
            return L.t(entry.signedUp ? "stage.waiting" : "status.no_signup")
        case .ready:
            if let ends, ends == today { return L.t("status.today") }
            if let ends, today.days(until: ends) <= 2 { return L.t("status.soon") }
            return L.t("status.ready")
        case .claimed: return L.t("stage.claimed")
        case .past: return L.t(entry.archived ? "status.archived" : "status.ended")
        }
    }

    func sortDay(on today: Day) -> Day? {
        switch stage(on: today) {
        case .signup: return signupBy ?? ends
        case .waiting:
            if let opens, opens >= today { return opens }
            return ends ?? opens
        case .ready, .past: return ends
        case .claimed: return entry.claimed
        }
    }

    func activeAcrossYears(on today: Day) -> Bool {
        guard entry.claimed == nil, !entry.archived, ends.map({ $0 < today }) != true else { return false }
        return (needsSignup && signupBy.map { $0 >= today } == true) || ends.map { $0 >= today } == true
    }

    static func sorted(_ rows: [Self], on today: Day) -> [Self] {
        rows.sorted { lhs, rhs in
            let left = lhs.sortDay(on: today), right = rhs.sortDay(on: today)
            if let left, let right, left != right {
                let newestFirst = lhs.stage(on: today) == .claimed && rhs.stage(on: today) == .claimed
                return newestFirst ? left > right : left < right
            }
            if (left == nil) != (right == nil) { return left != nil }
            let order = lhs.entry.merchant.name.localizedStandardCompare(rhs.entry.merchant.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct Starter: Identifiable {
    let id: String
    let brand: String
    let giftKey: String
    let offset: Int?

    static let all: [Self] = [
        .init(id: "starbucks", brand: "Starbucks", giftKey: "starter.drink", offset: -7),
        .init(id: "sephora", brand: "Sephora", giftKey: "starter.beauty", offset: nil),
        .init(id: "ulta", brand: "Ulta Beauty", giftKey: "starter.beauty", offset: nil),
        .init(id: "krispy", brand: "Krispy Kreme", giftKey: "starter.sweet", offset: nil),
        .init(id: "panera", brand: "Panera Bread", giftKey: "starter.reward", offset: nil),
        .init(id: "chick", brand: "Chick-fil-A", giftKey: "starter.reward", offset: -1),
        .init(id: "bundt", brand: "Nothing Bundt Cakes", giftKey: "starter.cake", offset: nil)
    ]

    func entry(year: Int) -> OfferEntry {
        OfferEntry(year: year, merchant: OfferValue(name: brand, gift: L.t(giftKey)), starterID: id,
                   signup: .yes, signupBy: offset.map { .relative($0) })
    }
}
