import SwiftUI
import WidgetKit

struct BirthdayWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshot
}

struct BirthdayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BirthdayWidgetEntry {
        let today = Day(Date())
        let birthday = today.adding(8)
        return BirthdayWidgetEntry(date: Date(), data: WidgetSnapshot(
            birthday: Birthday(month: birthday.month, day: birthday.day), hasOffers: true,
            candidates: [.init(id: UUID(), name: "Maple & Rye", signupBy: nil, opens: today, ends: today.adding(1))]))
    }

    func getSnapshot(in context: Context, completion: @escaping (BirthdayWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) :
            BirthdayWidgetEntry(date: Date(), data: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BirthdayWidgetEntry>) -> Void) {
        let calendar = BirthdayDates.calendar()
        let now = Date()
        let data = WidgetSnapshot.read()
        let start = calendar.startOfDay(for: now)
        let entries = [BirthdayWidgetEntry(date: now, data: data)] + (1...7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { BirthdayWidgetEntry(date: $0, data: data) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct BirthdayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BirthdayWidgetEntry

    private var today: Day { Day(entry.date) }
    private var birthday: Day? { entry.data.birthday?.next(from: today) }
    private var baseLink: AppLink { birthday == nil ? .birthday : .home }

    var body: some View {
        HStack(spacing: 12) {
            countdown
                .frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                Divider()
                deadlines.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Palette.ink)
        .widgetURL(baseLink.url)
        .containerBackground(for: .widget) { Palette.paper }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("birthday.your")).font(.caption.weight(.bold)).foregroundStyle(Palette.deep)
            if let birthday {
                Text(L.f("birthday.countdown", today.days(until: birthday))).font(.title2.bold())
                    .minimumScaleFactor(0.64).lineLimit(2)
                Text(birthday.label(.dateTime.month(.wide).day())).font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text(L.t("birthday.set")).font(.headline)
            }
        }
    }

    private var deadlines: some View {
        let due = entry.data.nextDue(on: today)
        let link: AppLink = due.map { .offer($0.id) } ?? (entry.data.hasOffers ? .home : .create)
        return Link(destination: link.url) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.f("widget.ready", entry.data.readyCount(on: today))).font(.caption.weight(.bold))
                    .foregroundStyle(Palette.deep)
                if let due, let date = due.deadline(on: today) {
                    Text(due.name).font(.subheadline.bold()).lineLimit(2)
                    Text(date == today ? L.t("widget.due_today") : L.f("widget.due", date.label()))
                        .font(.caption2.weight(.bold)).padding(4)
                        .background(Palette.gold, in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(L.t(entry.data.hasOffers ? "widget.no_due" : "action.add")).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}

@main struct BirthdayFreebiesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: BirthdayWidgetProvider()) { entry in
            BirthdayWidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("app.title"))
        .description(L.t("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
