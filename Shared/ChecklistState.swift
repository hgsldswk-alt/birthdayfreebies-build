import Foundation

struct CycleValue: Codable, Equatable, Sendable {
    var year: Int
    var milestones: Set<Int> = []
}

struct Preferences: Codable, Equatable, Sendable {
    var birthday: Birthday?
    var activeYear: Int?
    var birthdayReminders = false
    var offerReminders = false
    var activeDays: Set<Day> = []
    var reviewPending = false
    var reviewedVersion: String?

    func reviewEligible(claims: Int) -> Bool { claims >= 3 && activeDays.count >= 3 }
}

struct ChecklistState: Equatable, Sendable {
    var preferences = Preferences()
    var cycles: [Int: CycleValue] = [:]
    var entries: [OfferEntry] = []

    func year(on today: Day) -> Int {
        preferences.activeYear ?? preferences.birthday?.next(from: today).year ?? today.year
    }

    mutating func select(_ year: Int) {
        if cycles[year] == nil { cycles[year] = CycleValue(year: year) }
        preferences.activeYear = year
    }

    func resolved(calendar: Calendar = BirthdayDates.calendar()) -> [ResolvedOffer] {
        entries.map { $0.resolved(birthday: preferences.birthday, calendar: calendar) }
    }

    func currentRows(on today: Day) -> [ResolvedOffer] {
        let current = year(on: today)
        return resolved().filter {
            $0.entry.year == current || $0.activeAcrossYears(on: today)
        }
    }

    func rows(in year: Int) -> [OfferEntry] { entries.filter { $0.year == year } }
    func claimCount(in year: Int) -> Int { rows(in: year).filter { $0.claimed != nil }.count }
    func claimIDs(in year: Int) -> Set<UUID> {
        Set(rows(in: year).filter { $0.claimed != nil }.map(\.id))
    }

    func shouldReuse(on today: Day) -> Bool {
        guard let birthday = preferences.birthday else { return false }
        let current = year(on: today)
        let rows = resolved().filter { $0.entry.year == current && !$0.entry.archived }
        guard !rows.isEmpty else { return false }
        let cutoff = rows.compactMap(\.ends).max() ?? birthday.inYear(current)
        return today > cutoff
    }

    @discardableResult
    mutating func reuse(from source: Int, on today: Day) -> Int? {
        guard preferences.birthday != nil else { return nil }
        let target = source + 1
        if cycles[target] == nil {
            entries += rows(in: source).filter { !$0.archived }.map { $0.reused(in: target) }
        }
        select(target)
        return target
    }

    @discardableResult
    mutating func add(_ entries: [OfferEntry], in year: Int, portable: Bool = false) -> [UUID] {
        let existing = rows(in: year)
        var keys = Set(existing.map { portable ? $0.merchant.portableKey : $0.merchant.key })
        var added: [UUID] = []
        for row in entries {
            let key = portable ? row.merchant.portableKey : row.merchant.key
            if keys.insert(key).inserted {
                self.entries.append(row)
                added.append(row.id)
            }
        }
        if !added.isEmpty { select(year) }
        return added
    }

    mutating func update(_ id: UUID, change: (inout OfferEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    @discardableResult
    mutating func claim(_ id: UUID, day: Day, on today: Day, backfill: Bool = false) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }), day <= today else { return false }
        let row = entries[index]
        let stage = row.resolved(birthday: preferences.birthday).stage(on: today)
        guard row.claimed == nil, !row.archived, stage == .ready || (backfill && stage == .past) else { return false }
        entries[index].claimed = day
        let count = claimCount(in: row.year)
        if count == 1 || count == 10 { cycles[row.year, default: CycleValue(year: row.year)].milestones.insert(count) }
        return true
    }

    mutating func recordUse(on today: Day, year: Int, version: String) {
        if preferences.activeDays.count < 3 { preferences.activeDays.insert(today) }
        guard preferences.reviewedVersion != version else { return }
        if year == self.year(on: today), preferences.reviewEligible(claims: claimIDs(in: year).count) {
            preferences.reviewPending = true
        }
    }
}
