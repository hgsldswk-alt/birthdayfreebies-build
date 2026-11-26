import SwiftUI

struct StarterPage: View {
    @EnvironmentObject private var store: ChecklistStore
    @State private var added: [String: OfferEntry] = [:]
    @State private var pending = Set<String>()

    var body: some View {
        Page {
            BackHeader(title: L.t("starter.title"), overline: L.t("starter.overline"))
            Notice(title: L.t("starter.notice"))
            Panel(padded: false) {
                ForEach(Starter.all) { starter in
                    let existing = match(starter)
                    let artwork = OfferArtwork(name: starter.brand, gift: L.t(starter.giftKey), starterID: starter.id)
                    if starter.id != Starter.all.first?.id { Divider() }
                    ChoiceRow(title: starter.brand, detail: description(starter), selected: existing != nil,
                              id: "starter." + starter.id, symbol: artwork.symbol, tone: artwork.tone) {
                        Task { await toggle(starter) }
                    }
                    .disabled((existing != nil && existing != added[starter.id]) || pending.contains(starter.id))
                }
            }
            Text(L.f("starter.added", added.count)).font(.footnote).foregroundStyle(Palette.muted)
        }
    }

    private func match(_ starter: Starter) -> OfferEntry? {
        let key = starter.entry(year: store.year).merchant.key
        return store.state.rows(in: store.year).first { $0.starterID == starter.id || $0.merchant.key == key }
    }

    private func description(_ starter: Starter) -> String {
        let timing: String
        switch starter.id {
        case "starbucks": timing = L.t("starter.seven")
        case "chick": timing = L.t("starter.one")
        default: timing = L.t("starter.unknown")
        }
        return L.f("starter.summary", L.t(starter.giftKey), timing)
    }

    private func toggle(_ starter: Starter) async {
        guard pending.insert(starter.id).inserted else { return }
        defer { pending.remove(starter.id) }
        let year = store.year
        if let original = added[starter.id], match(starter) == original {
            if await store.change(core: false, { $0.entries.removeAll { $0 == original } }) { added[starter.id] = nil }
        } else if match(starter) == nil {
            let entry = starter.entry(year: year)
            var inserted = false
            if await store.change({ inserted = !$0.add([entry], in: year).isEmpty }), inserted {
                added[starter.id] = entry
            }
        }
    }
}

struct OfferEditor: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var entry: OfferEntry
    @State private var invalidKey: String?
    let new: Bool

    init(initial: OfferEntry, new: Bool) {
        _entry = State(initialValue: initial)
        self.new = new
    }

    var body: some View {
        VStack(spacing: 0) {
            Page {
                HeroCard {
                    BackHeader(title: L.t(new ? "action.add" : "offer.edit"), subtitle: L.t("offer.editor_hint"),
                               cancel: true)
                    HStack {
                        StatusPill(title: L.t(entry.checked ? "offer.checked" : "status.verify"),
                                   tone: entry.checked ? .mint : .butter)
                        Spacer(minLength: 0)
                        DesignIcon(symbol: new ? "gift.fill" : "pencil", tone: .mint)
                    }
                }
                Panel {
                    fieldHeading("offer.merchant", symbol: "storefront", tone: .mint)
                    TextField(L.t("offer.merchant_hint"), text: $entry.merchant.name)
                        .textInputAutocapitalization(.words).focused($nameFocused)
                        .fieldStyle().accessibilityIdentifier("editor.name")
                    field("offer.gift", hint: "offer.gift_hint", text: $entry.merchant.gift, id: "editor.gift")
                }
                if let invalidKey { Notice(title: L.t(invalidKey)) }
                Panel {
                    fieldHeading("offer.registration", symbol: "person.badge.plus", tone: .butter)
                    requirementPicker("offer.require_signup", selection: $entry.signup, id: "editor.signup")
                    if entry.signup != .no {
                        RuleField(title: L.t("offer.signup_by"), id: "editor.signup_by", rule: $entry.signupBy,
                                  today: store.today)
                    }
                    if !new && entry.signup != .no {
                        Toggle(L.t("action.signed"), isOn: $entry.signedUp).accessibilityIdentifier("editor.signed")
                    }
                }
                Panel {
                    fieldHeading("offer.window", symbol: "calendar", tone: .blue)
                    RuleField(title: L.t("offer.opens"), id: "editor.opens", rule: $entry.opens, today: store.today)
                    RuleField(title: L.t("offer.ends"), id: "editor.ends", rule: $entry.ends, today: store.today)
                    Text(L.t("offer.relative_hint")).font(.caption).foregroundStyle(Palette.muted)
                }
                Panel {
                    fieldHeading("offer.conditions", symbol: "checklist", tone: .coral)
                    requirementPicker("offer.purchase", selection: $entry.purchase, id: "editor.purchase")
                    field("offer.location", hint: "offer.location_hint", text: $entry.merchant.location, id: "editor.location")
                    field("offer.notes", hint: "offer.notes_hint", text: $entry.notes, id: "editor.notes", multiline: true)
                    Toggle(L.t("offer.check"), isOn: $entry.checked).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("editor.checked")
                }
            }
            PrimaryButton(L.t("offer.save"), id: "editor.save", symbol: "checkmark") { Task { await save() } }
                .frame(maxWidth: 538)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .disabled(OfferKey(name: entry.merchant.name, gift: "", location: "").name.isEmpty || store.saving)
        }
        .background(DesignStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if new && !Launch.arguments.contains("-shot") { nameFocused = true }
        }
    }

    private func fieldHeading(_ title: String, symbol: String, tone: DesignTone) -> some View {
        IconRow(title: L.t(title), symbol: symbol, tone: tone, heading: true)
    }

    private func field(_ title: String, hint: String, text: Binding<String>, id: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t(title)).font(.subheadline.weight(.semibold))
            TextField(L.t(hint), text: text, axis: multiline ? .vertical : .horizontal)
                .fieldStyle().accessibilityIdentifier(id)
        }
    }

    private func requirementPicker(_ title: String, selection: Binding<Requirement>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t(title)).font(.subheadline.weight(.semibold))
            Picker(L.t(title), selection: selection) {
                ForEach([Requirement.no, .yes, .unknown]) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier(id)
        }
    }

    private func save() async {
        var cleaned = entry
        cleaned.merchant.name = entry.merchant.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.merchant.gift = entry.merchant.gift.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.merchant.location = entry.merchant.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.merchant.name.count <= 80, cleaned.merchant.gift.count <= 80,
              cleaned.merchant.name.utf8.count <= 320, cleaned.merchant.gift.utf8.count <= 320,
              cleaned.merchant.location.count <= 200, cleaned.notes.count <= 4000 else {
            invalidKey = "offer.long"
            return
        }
        if cleaned.signup == .no { cleaned.signupBy = nil }
        let dates = cleaned.resolved(birthday: store.state.preferences.birthday)
        if let starts = dates.opens, let ends = dates.ends, starts > ends {
            invalidKey = "offer.bad_window"
            return
        }
        if let starts = cleaned.opens?.offset, let ends = cleaned.ends?.offset, starts > ends {
            invalidKey = "offer.bad_window"
            return
        }
        if store.state.rows(in: cleaned.year).contains(where: { $0.id != cleaned.id && $0.merchant.key == cleaned.merchant.key }) {
            invalidKey = "offer.duplicate"
            return
        }
        if await store.change({ state in
            if new { state.add([cleaned], in: cleaned.year) }
            else { state.update(cleaned.id) { $0 = cleaned } }
        }) { dismiss() }
    }
}

private struct RuleField: View {
    let title: String
    let id: String
    @Binding var rule: DateRule?
    let today: Day

    private var mode: Int {
        switch rule {
        case .none: return 0
        case .some(.fixed): return 1
        case .some(.relative): return 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(title, selection: Binding(get: { mode }, set: changeMode)) {
                Text(L.t("date.unknown")).tag(0)
                Text(L.t("date.fixed")).tag(1)
                Text(L.t("date.relative")).tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minHeight: 44)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id + ".mode")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .leading) {
                Text(title).font(.subheadline.weight(.medium)).allowsHitTesting(false).accessibilityHidden(true)
            }

            if case .some(.fixed(let value)) = rule {
                let calendar = BirthdayDates.calendar()
                DatePicker(title, selection: Binding(get: { value.date(in: calendar) ?? Date() }, set: {
                    rule = .fixed(Day($0, calendar: calendar))
                }), displayedComponents: .date)
                .environment(\.calendar, calendar)
                .labelsHidden()
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id + ".date")
            } else if let offset = rule?.offset {
                Stepper(value: Binding(get: { offset }, set: { rule = .relative($0) }), in: -366...366) {
                    Text(offset == 0 ? L.t("date.on_birthday") :
                        L.f(offset < 0 ? "date.before" : "date.after", abs(offset)))
                    .font(.footnote)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier(id + ".relative")
            }
        }
    }

    private func changeMode(_ value: Int) {
        guard value != mode else { return }
        switch value {
        case 1: rule = .fixed(today)
        case 2: rule = .relative(0)
        default: rule = nil
        }
    }
}

struct OfferDetail: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingArchive = false
    let id: UUID
    let open: (Route) -> Void

    var body: some View {
        Group {
            if let entry = store.state.entries.first(where: { $0.id == id }) {
                detail(entry.resolved(birthday: store.state.preferences.birthday))
            } else {
                Page {
                    BackHeader(title: L.t("app.title"))
                    EmptyReturn(message: L.t("offer.missing"), id: "detail.empty.back")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { FeedbackBar(open: open) }
    }

    private func detail(_ row: ResolvedOffer) -> some View {
        let entry = row.entry
        let stage = row.stage(on: store.today)
        let status = row.status(on: store.today)
        let artwork = OfferArtwork(entry)
        let urgent = stage == .ready && (row.ends.map { store.today.days(until: $0) <= 2 } ?? false)
        return Page {
            PageHeader(title: entry.merchant.name, subtitle: entry.merchant.gift) {
                VStack(spacing: 0) {
                    ActionButton(L.t("action.edit"), id: "detail.edit", symbol: "pencil") { open(.edit(id)) }
                    ActionButton(L.t("action.back"), id: "nav.back", symbol: "chevron.left") { dismiss() }
                }
            }
            HeroCard {
                IconRow(title: status,
                        detail: entry.priorSignupYear.map { L.f("offer.prior", String($0)) } ?? "",
                        symbol: artwork.symbol, tone: artwork.tone) {
                    if status != stage.title {
                        StatusPill(title: stage.title, tone: stage.pillTone(urgent: urgent))
                    }
                }
            }
            Panel {
                SectionTitle(title: L.t("offer.dates"))
                value(L.t("offer.signup_by"), row.signupBy?.label(.dateTime.year().month().day()))
                Divider()
                value(L.t("offer.opens"), row.opens?.label(.dateTime.year().month().day()))
                Divider()
                value(L.t("offer.ends"), row.ends?.label(.dateTime.year().month().day()))
                if let claimed = entry.claimed {
                    Divider()
                    claimDatePicker(claimed)
                }
            }
            Panel {
                SectionTitle(title: L.t("offer.conditions"))
                value(L.t("offer.registration"), entry.signedUp ? L.t("action.signed") : entry.signup.title)
                value(L.t("offer.purchase"), entry.purchase.title)
                if !entry.merchant.location.isEmpty { value(L.t("offer.location"), entry.merchant.location) }
                if !entry.notes.isEmpty { Text(entry.notes).font(.subheadline) }
                StatusPill(title: L.t(entry.checked ? "offer.checked" : "status.verify"),
                           tone: entry.checked ? .mint : .butter)
            }
            if stage == .signup && !entry.archived {
                PrimaryButton(L.t("action.mark_signed"), id: "detail.signup", symbol: "person.badge.plus") {
                    Task { await store.signUp(id) }
                }
            } else if stage == .ready {
                PrimaryButton(L.t("action.claim"), id: "detail.claim", symbol: "checkmark") {
                    Task { await store.claim(id) }
                }
            } else if stage == .past && !entry.archived {
                PrimaryButton(L.t("action.record"), id: "detail.record", symbol: "checkmark") {
                    Task { await store.claim(id, day: store.today) }
                }
            }
            ActionButton(L.t(entry.archived ? "action.unarchive" : "action.archive"), id: "detail.archive",
                         kind: .outline, symbol: "archivebox") {
                if entry.archived { Task { await store.change { $0.update(id) { $0.archived = false } } } }
                else { confirmingArchive = true }
            }
        }
        .disabled(store.saving)
        .alert(L.t("offer.archive_title"), isPresented: $confirmingArchive) {
            Button(L.t("action.archive"), role: .destructive) { Task { await store.change { $0.update(id) { $0.archived = true } } } }
            Button(L.t("action.cancel"), role: .cancel) {}
        } message: { Text(L.t("offer.archive_message")) }
    }

    private func claimDatePicker(_ claimed: Day) -> some View {
        let calendar = BirthdayDates.calendar()
        let value = Binding(get: { claimed.date(in: calendar) ?? store.now }, set: { date in
            let selected = Day(date, calendar: calendar)
            guard selected <= store.today else { return }
            Task {
                await store.change { state in
                    state.update(id) { if $0.claimed != nil { $0.claimed = selected } }
                }
            }
        })
        return DatePicker(L.t("offer.claimed_on"), selection: value,
                          in: ...(store.today.date(in: calendar, hour: 23) ?? store.now),
                          displayedComponents: .date)
            .environment(\.calendar, calendar)
            .frame(minHeight: 44)
            .accessibilityIdentifier("detail.claim_date")
    }

    private func value(_ title: String, _ contents: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.footnote).foregroundStyle(Palette.muted)
            Spacer(minLength: 10)
            Text(contents ?? L.t("date.unknown")).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }
}
