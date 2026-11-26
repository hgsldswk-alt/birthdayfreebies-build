import Foundation
import UserNotifications

@MainActor final class LocalReminders {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "birthdayfreebies."
    private var latest: [ScheduledReminder]?
    private var driver: Task<Void, Never>?

    func authorization() async -> UNAuthorizationStatus {
        if Launch.testing { return .denied }
        return await center.notificationSettings().authorizationStatus
    }

    func request() async throws -> UNAuthorizationStatus {
        if Launch.testing { return .denied }
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorization()
    }

    func update(_ reminders: [ScheduledReminder]) {
        guard !Launch.testing else { return }
        latest = reminders
        guard driver == nil else { return }
        driver = Task {
            while let plan = latest {
                latest = nil
                await replace(with: plan)
            }
            driver = nil
        }
    }

    private func replace(with plan: [ScheduledReminder]) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        let status = await authorization()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let calendar = BirthdayDates.calendar()
        for item in plan where latest == nil && item.fireAt > Date() {
            let content = UNMutableNotificationContent()
            content.title = L.t("reminder.title")
            let first = item.events.first?.title ?? ""
            content.body = item.events.count == 1 ? first : L.f("reminder.merged", first, item.events.count - 1)
            content.sound = .default
            content.userInfo = ["route": AppLink.due(item.day).url.absoluteString]
            var date = calendar.dateComponents([.year, .month, .day], from: item.fireAt)
            date.hour = 9
            date.minute = 0
            date.calendar = calendar
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: prefix + String(item.day.raw),
                                                           content: content, trigger: trigger))
            } catch {
                NSLog("BirthdayFreebies could not schedule a local reminder.")
            }
        }
    }
}
