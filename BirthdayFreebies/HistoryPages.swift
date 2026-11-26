import SwiftUI

struct HistoryPage: View {
    @EnvironmentObject private var store: ChecklistStore
    let open: (Route) -> Void

    var body: some View {
        Page {
            BackHeader(title: L.t("action.history"))
            let years = store.state.cycles.keys.sorted(by: >)
            if years.isEmpty { EmptyReturn(message: L.t("history.empty"), id: "history.empty.back") }
            ForEach(years, id: \.self) { year in
                Button { open(.cycle(year)) } label: {
                    Panel {
                        IconRow(title: L.f("home.year", String(year)),
                                detail: L.f("stats.fraction", store.state.claimCount(in: year),
                                            store.state.rows(in: year).count),
                                symbol: "calendar", tone: .blue) {
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.muted).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("history.year.\(year)")
            }
        }
    }
}

struct CyclePage: View {
    @EnvironmentObject private var store: ChecklistStore
    let year: Int
    let open: (Route) -> Void
    let reuse: () -> Void

    var body: some View {
        Page {
            BackHeader(title: L.f("home.year", String(year)))
            if store.state.preferences.birthday != nil && !store.state.rows(in: year).isEmpty {
                PrimaryButton(L.t("action.reuse"), id: "history.reuse", symbol: "arrow.clockwise", action: reuse)
                    .disabled(store.saving)
            } else if store.state.preferences.birthday == nil {
                ActionButton(L.t("birthday.set"), id: "history.birthday", kind: .outline, symbol: "calendar") {
                    open(.birthday)
                }
            }
            OfferCollection(rows: rows, open: open)
        }
    }

    private var rows: [ResolvedOffer] {
        let rows = store.state.rows(in: year).map { $0.resolved(birthday: store.state.preferences.birthday) }
        return OfferStage.allCases.flatMap { stage in
            ResolvedOffer.sorted(rows.filter { $0.stage(on: store.today) == stage }, on: store.today)
        }
    }
}

struct PastPage: View {
    @EnvironmentObject private var store: ChecklistStore
    let open: (Route) -> Void

    var body: some View {
        Page {
            BackHeader(title: L.t("stage.past"))
            OfferCollection(rows: rows, open: open)
        }
    }

    private var rows: [ResolvedOffer] {
        let rows = store.state.resolved()
        return ResolvedOffer.sorted(rows.filter { $0.stage(on: store.today) == .past }, on: store.today)
    }
}

struct DuePage: View {
    @EnvironmentObject private var store: ChecklistStore
    let day: Day
    let open: (Route) -> Void

    var body: some View {
        Page {
            BackHeader(title: L.t("reminder.due"), subtitle: day.label(.dateTime.weekday().month().day()))
            let events = ReminderPlan.events(state: store.state, on: store.today)
                .filter { $0.alertDays.contains(day) }
            if events.isEmpty { EmptyReturn(message: L.t("history.empty"), id: "due.empty.back") }
            ForEach(events, id: \.self) { event in
                Button {
                    if let id = event.offerID { open(.detail(id)) }
                    else { open(.birthday) }
                } label: {
                    Panel {
                        IconRow(title: event.title, detail: event.due.label(), symbol: "bell", tone: .butter) {
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.muted).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("due." + (event.offerID?.uuidString ?? "birthday"))
            }
        }
    }
}

private struct OfferCollection: View {
    let rows: [ResolvedOffer]
    let open: (Route) -> Void

    var body: some View {
        if rows.isEmpty { EmptyReturn(message: L.t("history.empty"), id: "offers.empty.back") }
        else {
            Panel(padded: false) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    OfferLine(row: row, open: open)
                }
            }
        }
    }
}
