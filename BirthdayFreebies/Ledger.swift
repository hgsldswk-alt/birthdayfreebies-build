import Foundation
import SwiftData

@Model final class Offer {
    @Attribute(.unique) var id: UUID
    var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

@Model final class BirthdayCycle {
    @Attribute(.unique) var year: Int
    var payload: Data

    init(year: Int, payload: Data) {
        self.year = year
        self.payload = payload
    }
}

@Model final class CycleOffer {
    @Attribute(.unique) var id: UUID
    var merchantID: UUID
    var year: Int
    var payload: Data

    init(entry: OfferEntry, payload: Data) {
        id = entry.id
        merchantID = entry.merchant.id
        year = entry.year
        self.payload = payload
    }
}

@Model final class LocalPreferences {
    var payload: Data

    init(payload: Data) { self.payload = payload }
}

@ModelActor actor Ledger {
    static func open(inMemory: Bool) throws -> Ledger {
        let schema = Schema([Offer.self, BirthdayCycle.self, CycleOffer.self, LocalPreferences.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return Ledger(modelContainer: container)
    }

    func load() throws -> ChecklistState {
        let decoder = JSONDecoder()
        let cycles = try modelContext.fetch(FetchDescriptor<BirthdayCycle>()).map {
            try decoder.decode(CycleValue.self, from: $0.payload)
        }
        let entries = try modelContext.fetch(FetchDescriptor<CycleOffer>()).map {
            try decoder.decode(OfferEntry.self, from: $0.payload)
        }
        let preference = try modelContext.fetch(FetchDescriptor<LocalPreferences>()).first
        return try ChecklistState(preferences: preference.map {
            try decoder.decode(Preferences.self, from: $0.payload)
        } ?? Preferences(), cycles: Dictionary(uniqueKeysWithValues: cycles.map { ($0.year, $0) }),
        entries: entries)
    }

    func save(_ state: ChecklistState, replacing previous: ChecklistState) throws {
        modelContext.autosaveEnabled = false
        do {
            let encoder = JSONEncoder()
            if state.preferences != previous.preferences {
                let data = try encoder.encode(state.preferences)
                if let row = try modelContext.fetch(FetchDescriptor<LocalPreferences>()).first {
                    row.payload = data
                } else {
                    modelContext.insert(LocalPreferences(payload: data))
                }
            }
            if state.cycles != previous.cycles {
                let persisted = try modelContext.fetch(FetchDescriptor<BirthdayCycle>())
                let cycles = Dictionary(uniqueKeysWithValues: persisted.map { ($0.year, $0) })
                for value in state.cycles.values where value != previous.cycles[value.year] {
                    let data = try encoder.encode(value)
                    if let row = cycles[value.year] { row.payload = data }
                    else { modelContext.insert(BirthdayCycle(year: value.year, payload: data)) }
                }
            }
            if state.entries != previous.entries {
                let prior = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.id, $0) })
                let records = try modelContext.fetch(FetchDescriptor<CycleOffer>())
                let merchants = try modelContext.fetch(FetchDescriptor<Offer>())
                let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
                var knownMerchants = Set(merchants.map(\.id))
                let newIDs = Set(state.entries.map(\.id))
                for row in records where !newIDs.contains(row.id) { modelContext.delete(row) }
                for entry in state.entries where entry != prior[entry.id] {
                    if knownMerchants.insert(entry.merchant.id).inserted {
                        modelContext.insert(Offer(id: entry.merchant.id, name: entry.merchant.name))
                    }
                    let data = try encoder.encode(entry)
                    if let row = byID[entry.id] { row.payload = data }
                    else { modelContext.insert(CycleOffer(entry: entry, payload: data)) }
                }
                let usedMerchants = Set(state.entries.map { $0.merchant.id })
                for merchant in merchants where !usedMerchants.contains(merchant.id) { modelContext.delete(merchant) }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func publishWidget(_ state: ChecklistState, on today: Day) throws {
        try WidgetSnapshot.make(from: state, on: today).write()
    }
}
