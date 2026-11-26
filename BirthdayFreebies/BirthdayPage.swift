import SwiftUI
import UIKit
import UserNotifications

struct BirthdayPage: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var draft = Birthday(month: 1, day: 1)

    private var prefs: Preferences { store.state.preferences }
    private var hasBirthday: Bool { prefs.birthday != nil }
    private var calendar: Calendar { BirthdayDates.calendar() }

    var body: some View {
        Page {
            BackHeader(title: L.t("birthday.reminders"),
                       subtitle: store.upcomingBirthday?.label(.dateTime.weekday(.wide).month(.wide).day()))
            if let birth = store.upcomingBirthday, !editing { countdown(birth) }
            if editing || !hasBirthday {
                editor
            } else {
                Panel {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            SectionTitle(title: L.t("birthday.label"))
                            Text(prefs.birthday?.inYear(2000).label(.dateTime.month(.wide).day()) ?? "")
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        ActionButton(L.t("birthday.edit"), id: "birthday.edit") { beginEdit() }
                    }
                }
            }
            if !editing { reminderSection }
            if !editing, let next = store.nextReminder, !notificationsUnavailable {
                Panel {
                    SectionTitle(title: L.t("reminder.next"))
                    Text(L.f("reminder.when", next.day.label(), next.events.first?.title ?? ""))
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text(L.t("birthday.leap")).font(.footnote).foregroundStyle(Palette.muted)
        }
        .onAppear {
            if !hasBirthday { beginEdit() }
        }
    }

    private var notificationsUnavailable: Bool {
        store.notificationStatus == .denied || store.notificationStatus == .notDetermined
    }

    private var editor: some View {
        Panel {
            SectionTitle(title: L.t("birthday.set"))
            HStack {
                Picker(L.t("birthday.month"), selection: $draft.month) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Day(year: 2000, month: month, day: 1).label(.dateTime.month(.wide))).tag(month)
                    }
                }
                .accessibilityIdentifier("birthday.month")
                Picker(L.t("birthday.day"), selection: $draft.day) {
                    ForEach(1...daysInMonth(draft.month), id: \.self) { day in
                        Text(day.formatted()).tag(day)
                    }
                }
                .accessibilityIdentifier("birthday.day")
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .onChange(of: draft.month) { _, month in draft.day = min(draft.day, daysInMonth(month)) }
            if !hasBirthday {
                PrimaryButton(L.t("birthday.save_enable"), id: "birthday.save_enable", symbol: "bell.badge") {
                    Task { await save(enable: true) }
                }
                .disabled(store.saving)
            }
            ActionButton(L.t("birthday.save"), id: "birthday.save", kind: hasBirthday ? .primary : .outline,
                         symbol: "checkmark") {
                Task { await save(enable: false) }
            }
            .disabled(store.saving)
            if hasBirthday {
                ActionButton(L.t("action.cancel"), id: "birthday.cancel") { editing = false }
            }
        }
    }

    private func daysInMonth(_ month: Int) -> Int {
        let day = Day(year: 2000, month: month, day: 1)
        return day.date(in: calendar).flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
    }

    private func beginEdit() {
        let today = store.today
        draft = prefs.birthday ?? Birthday(month: today.month, day: today.day)
        editing = true
    }

    private func save(enable: Bool) async {
        var birthday = draft
        birthday.day = min(birthday.day, daysInMonth(birthday.month))
        if await store.setBirthday(birthday) {
            if enable { await store.enableReminders(birthday: true, offers: true) }
            editing = false
        }
    }

    private func countdown(_ day: Day) -> some View {
        HeroCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    CaptionLabel(title: L.t("birthday.until"))
                    Text(L.f("birthday.countdown", store.today.days(until: day)))
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .accessibilityIdentifier("birthday.countdown")
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                GiftIllustration(size: 58)
            }
        }
    }

    private var reminderSection: some View {
        Panel {
            SectionTitle(title: L.t("reminder.settings"))
            if !prefs.birthdayReminders && !prefs.offerReminders {
                PrimaryButton(L.t("reminder.enable"), id: "birthday.enable", symbol: "bell.badge") {
                    Task { await store.enableReminders(birthday: hasBirthday, offers: true) }
                }
                .disabled(store.saving)
            }
            Toggle(isOn: Binding(get: { prefs.birthdayReminders }, set: { on in
                Task { await store.enableReminders(birthday: on, offers: prefs.offerReminders) }
            })) {
                IconRow(title: L.t("reminder.birthday_toggle"), detail: L.t("reminder.birthday_rule"),
                        symbol: "birthday.cake.fill", tone: .butter)
            }
            .disabled(!hasBirthday || store.saving)
            .accessibilityIdentifier("birthday.toggle")
            Divider()
            Toggle(isOn: Binding(get: { prefs.offerReminders }, set: { on in
                Task { await store.enableReminders(birthday: prefs.birthdayReminders, offers: on) }
            })) {
                IconRow(title: L.t("reminder.offer_toggle"), detail: L.t("reminder.offer_rule"),
                        symbol: "bell", tone: .blue)
            }
            .disabled(store.saving)
            .accessibilityIdentifier("offer.toggle")
            Text(L.t("reminder.time")).font(.footnote).foregroundStyle(Palette.muted)
            if store.notificationStatus == .denied && (prefs.birthdayReminders || prefs.offerReminders) {
                Notice(title: L.t("reminder.denied")).accessibilityIdentifier("birthday.denied")
                ActionButton(L.t("reminder.system"), id: "birthday.system") {
                    if !Launch.testing, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if store.notificationStatus == .notDetermined && (prefs.birthdayReminders || prefs.offerReminders) {
                ActionButton(L.t("reminder.enable"), id: "birthday.enable") {
                    Task { await store.enableReminders(birthday: prefs.birthdayReminders, offers: prefs.offerReminders) }
                }
            }
        }
    }

}
