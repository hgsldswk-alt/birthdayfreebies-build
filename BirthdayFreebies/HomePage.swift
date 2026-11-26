import SwiftUI

struct HomePage: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 42
    @State private var showClaimed = false
    @AccessibilityFocusState private var focusedRow: UUID?
    let open: (Route) -> Void

    init(open: @escaping (Route) -> Void) {
        self.open = open
    }

    private var rows: [ResolvedOffer] { store.state.currentRows(on: store.today) }
    private var claimed: [ResolvedOffer] { sorted(.claimed) }

    var body: some View {
        Page {
            PageHeader(title: L.t("app.title"), overline: L.f("home.year", String(store.year))) {
                EmptyView()
            }
            summary
            if rows.isEmpty {
                EmptyIllustration(message: L.t("home.empty"), actionTitle: L.t("action.add"),
                                  actionSymbol: "plus", id: "home.add") { open(.create) }
            } else {
                PrimaryButton(L.t("action.add"), id: "home.add", symbol: "plus") { open(.create) }
            }
            shortcuts
            if !rows.isEmpty {
                ForEach([OfferStage.signup, .waiting, .ready], id: \.self) { stage in
                    section(stage)
                }
                claimedSection
            }
            if store.state.shouldReuse(on: store.today) {
                ActionButton(L.t("action.reuse"), id: "home.reuse", kind: .outline, symbol: "arrow.clockwise") {
                    let year = store.year, today = store.today
                    Task { await store.change(core: false) { $0.reuse(from: year, on: today) } }
                }
                .disabled(store.saving)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { FeedbackBar(open: open) }
    }

    private var summary: some View {
        let own = store.state.rows(in: store.year)
        let count = own.filter { $0.claimed != nil }.count
        let total = own.filter { !$0.archived || $0.claimed != nil }.count
        let compact = !typeSize.isAccessibilitySize
        let layout = compact ? AnyLayout(HStackLayout(spacing: 14))
                             : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        return HeroCard(prominent: compact) {
            layout {
                birthdayButton(onGreen: compact)
                Button { open(.stats) } label: {
                    VStack(spacing: 4) {
                        Text(L.t("stage.claimed")).font(.caption.weight(.semibold))
                        ProgressRing(count: count, total: total)
                            .accessibilityHidden(true)
                        summaryLink(L.t("action.stats"))
                    }
                    .foregroundStyle(Palette.deep)
                    .padding(8)
                    .frame(minWidth: 104)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(L.t("stage.claimed") + " " + L.f("stats.fraction", count, total) +
                                    ", " + L.t("action.stats"))
                .accessibilityIdentifier("home.stats")
            }
        }
    }

    private func birthdayButton(onGreen: Bool) -> some View {
        let birthday = store.upcomingBirthday
        return Button { open(.birthday) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    GiftIllustration(size: 48, onGreen: onGreen)
                    Text(L.t("birthday.your")).font(.caption.weight(.semibold))
                }
                Text(birthday.map { L.f("birthday.countdown", store.today.days(until: $0)) } ?? L.t("birthday.set"))
                    .font(.system(size: birthday == nil ? countdownSize * 0.67 : countdownSize,
                                  weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.77)
                    .fixedSize(horizontal: false, vertical: true)
                summaryLink(birthday.map { L.f("home.birthday_hint", $0.label()) } ?? L.t("birthday.reminders"))
            }
            .foregroundStyle(onGreen ? .white : Palette.deep)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("home.birthday")
    }

    private func summaryLink(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
        }
    }

    private var shortcuts: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: 10) {
            IconTile(title: L.t("action.starter"), symbol: "list.bullet.rectangle", tone: .butter,
                     id: "home.starter") { open(.starter) }
            IconTile(title: L.t("stage.past"), symbol: "calendar.badge.clock", tone: .coral,
                     id: "home.past") { open(.past) }
            IconTile(title: L.t("action.history"), symbol: "clock.arrow.circlepath", tone: .blue,
                     id: "home.history") { open(.history) }
            IconTile(title: L.t("action.import"), symbol: "square.and.arrow.down", tone: .mint,
                     id: "home.import") { open(.importCode) }
        }
    }

    private func sorted(_ stage: OfferStage) -> [ResolvedOffer] {
        ResolvedOffer.sorted(rows.filter { $0.stage(on: store.today) == stage }, on: store.today)
    }

    private func neighbor(of id: UUID, in offers: [ResolvedOffer]) -> UUID? {
        guard let i = offers.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < offers.count { return offers[i + 1].id }
        return i > 0 ? offers[i - 1].id : nil
    }

    private func section(_ stage: OfferStage) -> some View {
        let offers = sorted(stage)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: stage.title, count: offers.count)
            if !offers.isEmpty {
                Panel(padded: false) {
                    ForEach(offers) { row in
                        if row.id != offers.first?.id { Divider().overlay(Palette.line) }
                        OfferLine(row: row, selectable: true, open: open, focus: $focusedRow,
                                  neighbor: neighbor(of: row.id, in: offers))
                    }
                }
            }
        }
    }

    private var claimedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: OfferStage.claimed.title, count: claimed.count)
            if !claimed.isEmpty {
                Panel(padded: false) {
                    ChoiceRow(title: L.t(showClaimed ? "home.hide_claimed" : "home.show_claimed"),
                              detail: claimed.first.map { L.f("home.latest", $0.entry.merchant.name) } ?? "",
                              selected: true, id: "home.claimed") { showClaimed.toggle() }
                    if showClaimed {
                        ForEach(claimed) { row in
                            Divider().overlay(Palette.line)
                            OfferLine(row: row, open: open)
                        }
                    }
                }
            }
        }
    }
}

struct OfferLine: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let row: ResolvedOffer
    var selectable = false
    var open: (Route) -> Void
    var focus: AccessibilityFocusState<UUID?>.Binding? = nil
    var neighbor: UUID? = nil

    private var stage: OfferStage { row.stage(on: store.today) }

    var body: some View {
        let artwork = OfferArtwork(row.entry)
        let status = row.status(on: store.today)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            Button { open(.detail(row.id)) } label: {
                IconRow(title: row.entry.merchant.name, detail: summary,
                        symbol: artwork.symbol, tone: artwork.tone) {
                    HStack(spacing: 6) {
                        StatusPill(title: status, tone: stage.pillTone(urgent: urgent))
                        if !(selectable && (stage == .signup || stage == .ready)) {
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.muted).accessibilityHidden(true)
                        }
                    }
                }
                .padding(.leading, 11)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("offer.detail." + row.entry.merchant.name)
            .modifier(RowFocus(focus: focus, id: row.id))
            if selectable && stage == .signup {
                ActionButton(L.t("action.signed"), id: "offer.signup." + row.entry.merchant.name) {
                    Task { await store.signUp(row.id); moveFocus() }
                }
                .disabled(store.saving)
            } else if selectable && stage == .ready {
                ActionButton(L.t("action.claim"), id: "offer.claim." + row.entry.merchant.name) {
                    Task { if await store.claim(row.id) { moveFocus() } }
                }
                .disabled(store.saving)
            }
        }
        .padding(.trailing, 10)
    }

    private func moveFocus() {
        guard let focus, let neighbor else { return }
        focus.wrappedValue = neighbor
    }

    private var urgent: Bool { row.ends.map { store.today.days(until: $0) <= 2 } ?? false }

    private var summary: String {
        let gift = row.entry.merchant.gift
        let giftOrUnset = gift.isEmpty ? L.t("date.unknown") : gift
        switch stage {
        case .signup:
            guard let day = row.signupBy else { return giftOrUnset }
            if row.entry.signup == .unknown && day >= store.today { return day.label() }
            return L.f(day < store.today ? "row.missed" : "row.join", day.label())
        case .waiting:
            if let date = row.opens, date > store.today { return L.f("row.opens", date.label()) }
            return row.entry.signedUp ? giftOrUnset : L.t("status.no_signup")
        case .ready:
            let date = row.ends.map { L.f("row.until", $0.label()) } ?? ""
            return [gift, date].filter { !$0.isEmpty }.joined(separator: " · ")
        case .claimed: return row.entry.claimed?.label() ?? L.t("stage.claimed")
        case .past: return row.ends.map { L.f("row.until", $0.label()) } ?? giftOrUnset
        }
    }
}

struct FeedbackBar: View {
    @EnvironmentObject private var store: ChecklistStore
    let open: (Route) -> Void

    var body: some View {
        if let undo = store.undo {
            HStack {
                Text(L.t(undo.kind == .claim ? "feedback.claimed" : "feedback.signed"))
                    .font(.subheadline.weight(.semibold))
                if let milestone = store.milestone {
                    Text(L.t(milestone == 1 ? "milestone.first" : "milestone.tenth"))
                        .font(.caption).foregroundStyle(Palette.deep)
                }
                Spacer(minLength: 0)
                if store.milestone != nil {
                    ActionButton(L.t("action.viewCard"), id: "offer.milestoneCard") { open(.stats) }
                }
                ActionButton(L.t("action.undo"), id: "offer.undo") { Task { await store.revert() } }
                    .disabled(store.saving)
            }
            .padding(.horizontal, 12)
            .background(Palette.tint, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
            .background(DesignStyle.background)
        }
    }
}

private struct RowFocus: ViewModifier {
    let focus: AccessibilityFocusState<UUID?>.Binding?
    let id: UUID
    func body(content: Content) -> some View {
        if let focus { content.accessibilityFocused(focus, equals: id) } else { content }
    }
}
