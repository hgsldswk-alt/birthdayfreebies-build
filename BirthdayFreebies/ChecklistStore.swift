import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

struct UndoChange: Equatable {
    enum Kind: Equatable { case claim, signup }
    let id: UUID
    let kind: Kind
}

@MainActor final class ChecklistStore: ObservableObject {
    @Published private(set) var state = ChecklistState()
    @Published private(set) var now = Date()
    @Published private(set) var loaded = false
    @Published private(set) var saving = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var undo: UndoChange?
    @Published private(set) var milestone: Int?
    @Published var errorKey: String?

    private var ledger: Ledger?
    private let reminders = LocalReminders()
    private var feedbackTimer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []
    private static let demoNow = BirthdayDates.calendar().date(
        from: DateComponents(year: 2026, month: 11, day: 25, hour: 8)) ?? Date()

    var today: Day { Day(now) }
    var year: Int { state.year(on: today) }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var upcomingBirthday: Day? { state.preferences.birthday?.next(from: today) }
    var nextReminder: ScheduledReminder? { ReminderPlan.schedule(state: state, now: now).first }

    func start() async {
        guard ledger == nil, !loaded, !saving else { return }
        saving = true
        defer { finishSave() }
        now = Launch.seed ? Self.demoNow : Date()
        do {
            let memoryOnly = Launch.testing || Launch.reset
            let opened = try await Task.detached(priority: .userInitiated) {
                try Ledger.open(inMemory: memoryOnly)
            }.value
            var initial = try await opened.load()
            if Launch.seed {
                initial = DemoState.make(today: today)
                try await opened.save(initial, replacing: ChecklistState())
            }
            state = initial
            ledger = opened
            loaded = true
            refresh()
        } catch {
            self.errorKey = "error.open"
        }
    }

    func refresh() {
        now = Launch.seed ? Self.demoNow : Date()
        guard let ledger else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = state
        let day = today
        reminders.update(ReminderPlan.schedule(state: snapshot, now: now))
        refreshTask?.cancel()
        refreshTask = Task {
            notificationStatus = await reminders.authorization()
            guard !Launch.testing, !Task.isCancelled, generation == refreshGeneration else { return }
            do {
                try await ledger.publishWidget(snapshot, on: day)
                guard !Task.isCancelled, generation == refreshGeneration else { return }
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
            } catch {
                NSLog("BirthdayFreebies could not refresh the widget.")
            }
        }
    }

    @discardableResult
    func change(core: Bool = true, _ action: (inout ChecklistState) -> Void) async -> Bool {
        while saving {
            await withCheckedContinuation { saveWaiters.append($0) }
        }
        guard let ledger else { return false }
        saving = true
        defer { finishSave() }
        let previous = state
        var next = previous
        action(&next)
        guard next != previous else { return true }
        if core {
            next.recordUse(on: today, year: next.year(on: today), version: version)
        }
        do {
            try await ledger.save(next, replacing: previous)
            state = next
            refresh()
            return true
        } catch {
            self.errorKey = "error.save"
            return false
        }
    }

    private func finishSave() {
        saving = false
        let waiters = saveWaiters
        saveWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func setBirthday(_ birthday: Birthday) async -> Bool {
        let birthYear = birthday.next(from: today).year
        return await change(core: false) { state in
            state.preferences.birthday = birthday
            if state.entries.isEmpty {
                state.select(birthYear)
            }
        }
    }

    func enableReminders(birthday: Bool, offers: Bool) async {
        guard await change(core: false, { state in
            state.preferences.birthdayReminders = birthday
            state.preferences.offerReminders = offers
        }) else { return }
        let currentStatus = await reminders.authorization()
        notificationStatus = currentStatus
        guard (birthday || offers) && currentStatus == .notDetermined else { return }
        do {
            notificationStatus = try await reminders.request()
            refresh()
        } catch {
            self.errorKey = "error.notifications"
        }
    }

    func signUp(_ id: UUID) async {
        guard let row = state.entries.first(where: { $0.id == id }), !row.signedUp, !row.archived else { return }
        if await change({ $0.update(id) { $0.signedUp = true } }) {
            showFeedback(.init(id: id, kind: .signup))
        }
    }

    func claim(_ id: UUID, day: Day? = nil) async -> Bool {
        let previous = state
        let date = today
        var recorded = false
        guard await change({ recorded = $0.claim(id, day: day ?? date, on: date, backfill: day != nil) }),
              recorded else { return false }
        if let row = state.entries.first(where: { $0.id == id }) {
            let newMilestones = (state.cycles[row.year]?.milestones ?? [])
                .subtracting(previous.cycles[row.year]?.milestones ?? [])
            showFeedback(.init(id: id, kind: .claim), milestone: newMilestones.max())
        }
        return true
    }

    func revert() async {
        guard let undo else { return }
        if await change(core: false, { state in
            state.update(undo.id) {
                switch undo.kind {
                case .claim: $0.claimed = nil
                case .signup: $0.signedUp = false
                }
            }
        }) {
            feedbackTimer?.cancel()
            self.undo = nil
            milestone = nil
        }
    }

    private func showFeedback(_ change: UndoChange, milestone: Int? = nil) {
        undo = change
        self.milestone = milestone
        feedbackTimer?.cancel()
        feedbackTimer = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            undo = nil
            self.milestone = nil
        }
    }

    func takeReviewOpportunity() async -> Bool {
        guard !Launch.testing, undo == nil, milestone == nil, state.preferences.reviewPending,
              state.preferences.reviewedVersion != version,
              state.preferences.reviewEligible(claims: state.claimCount(in: year)),
              !saving else { return false }
        return await change(core: false) {
            $0.preferences.reviewPending = false
            $0.preferences.reviewedVersion = version
        }
    }

    func restoreReviewOpportunity() async {
        _ = await change(core: false) {
            $0.preferences.reviewPending = true
            $0.preferences.reviewedVersion = nil
        }
    }
}

private enum DemoState {
    static func make(today: Day) -> ChecklistState {
        var state = ChecklistState()
        let year = today.year
        state.preferences.birthday = Birthday(month: 12, day: 2)
        state.preferences.birthdayReminders = true
        state.preferences.offerReminders = true
        state.select(year)
        let starbucks = Starter.all[0].entry(year: year)
        var sephora = Starter.all[1].entry(year: year)
        sephora.signedUp = true
        sephora.checked = true
        sephora.opens = .relative(-1)
        sephora.ends = .relative(15)
        var bakery = OfferEntry(year: year, merchant: OfferValue(name: "Maple & Rye", gift: L.t("demo.pastry")),
                                signup: .no, purchase: .no, signupBy: nil, opens: .fixed(today.adding(-2)),
                                ends: .fixed(today), checked: true)
        bakery.notes = L.t("demo.terms")
        let books = OfferEntry(year: year, merchant: OfferValue(name: "Juniper Books", gift: L.t("demo.bookmark")),
                               signup: .no, purchase: .no, opens: .fixed(today), ends: .fixed(today.adding(5)),
                               checked: true)
        let past = OfferEntry(year: year, merchant: OfferValue(name: "Cedar Café"),
                              signup: .no, opens: .fixed(today.adding(-9)), ends: .fixed(today.adding(-1)))
        let names = ["Willow Tea", "Moss Coffee", "Olive Books", "Clover Café", "Elm Bakery", "Poppy Tea",
                     "Ivy Market", "Sage Café", "Birch Bakery", "Pear Books", "Aster Tea", "Acorn Coffee"]
        let claimed = names.enumerated().map { index, name in
            OfferEntry(year: year, merchant: OfferValue(name: name), signup: .no, purchase: .no,
                       checked: true, claimed: today.adding(-index))
        }
        let old = OfferEntry(year: year - 1, merchant: OfferValue(name: "Riverbend Bakery"), signedUp: true,
                             claimed: Day(year: year - 1, month: 12, day: 2))
        state.cycles[year - 1] = CycleValue(year: year - 1, milestones: [1])
        state.cycles[year]?.milestones = [1, 10]
        state.entries = [starbucks, sephora, bakery, books, past, old] + claimed
        return state
    }
}
