import Foundation

struct WidgetSnapshot: Codable, Sendable {
    static let group = "group.com.hgsldswk.birthdayfreebies"
    static let kind = "BirthdayFreebiesWidget"
    static let file = "birthday-widget.json"

    struct Candidate: Codable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let signupBy: Day?
        let opens: Day?
        let ends: Day?

        func ready(on day: Day) -> Bool {
            guard let opens, let ends else { return false }
            return opens <= day && day <= ends
        }

        func deadline(on day: Day) -> Day? {
            if let signupBy, signupBy >= day { return signupBy }
            if let ends, ends >= day { return ends }
            return nil
        }
    }

    var birthday: Birthday?
    var hasOffers = false
    var candidates: [Candidate] = []

    static func make(from state: ChecklistState, on today: Day) -> Self {
        let rows = state.currentRows(on: today)
        return Self(birthday: state.preferences.birthday, hasOffers: !rows.isEmpty, candidates: rows.compactMap { row in
            guard row.entry.claimed == nil, !row.entry.archived, row.stage(on: today) != .past else { return nil }
            let checkedWindow = row.entry.checked && row.validWindow && !row.needsSignup
            let signup = row.needsSignup ? row.signupBy : nil
            guard checkedWindow || signup != nil else { return nil }
            return Candidate(id: row.id, name: row.entry.merchant.name, signupBy: signup,
                             opens: checkedWindow ? row.opens : nil, ends: checkedWindow ? row.ends : nil)
        })
    }

    func readyCount(on day: Day) -> Int { candidates.filter { $0.ready(on: day) }.count }

    func nextDue(on day: Day) -> Candidate? {
        var best: Candidate?
        var bestDue: Day?
        for row in candidates {
            guard let due = row.deadline(on: day) else { continue }
            if let current = bestDue, let chosen = best {
                let earlier: Bool = due < current
                let tieWins: Bool = due == current && row.id.uuidString < chosen.id.uuidString
                if earlier || tieWins {
                    best = row
                    bestDue = due
                }
            } else {
                best = row
                bestDue = due
            }
        }
        return best
    }

    static func read() -> Self {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: folder.appendingPathComponent(file)),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return snapshot
    }

    func write() throws {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else { return }
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent(Self.file), options: .atomic)
    }
}
