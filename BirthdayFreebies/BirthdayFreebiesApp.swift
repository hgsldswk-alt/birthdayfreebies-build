import StoreKit
import SwiftUI
import UIKit
import UserNotifications

enum Route: Hashable {
    case starter, create, detail(UUID), edit(UUID), birthday, stats, importCode, history, cycle(Int), past, due(Day)
}

@MainActor private final class LinkInbox: ObservableObject {
    static let shared = LinkInbox()
    @Published var pending: AppLink?
}

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = (response.notification.request.content.userInfo["route"] as? String)
            .flatMap(URL.init(string:)).flatMap(AppLink.init(url:))
        Task { @MainActor in LinkInbox.shared.pending = link }
        completionHandler()
    }
}

@main struct BirthdayFreebiesApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var delegate
    @StateObject private var store = ChecklistStore()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Palette.accent)
        }
    }
}

struct AppRoot: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @StateObject private var inbox = LinkInbox.shared
    @State private var path: [Route] = []

    private var reviewReady: Bool {
        scenePhase == .active && path.isEmpty && store.undo == nil && store.milestone == nil &&
        store.errorKey == nil && store.state.preferences.reviewPending &&
        store.state.preferences.reviewedVersion != store.version &&
        store.state.preferences.reviewEligible(claims: store.state.claimCount(in: store.year))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.loaded { HomePage(open: navigate) }
                else {
                    Page {
                        PageHeader(title: L.t("app.title")) { EmptyView() }
                        if store.errorKey == nil { ProgressView().accessibilityLabel(L.t("app.loading")) }
                        else { ActionButton(L.t("action.retry"), id: "home.retry") { Task { await store.start() } } }
                    }
                }
            }
            .navigationDestination(for: Route.self, destination: destination)
        }
        .task { await store.start(); openPending() }
        .task(id: reviewReady) {
            guard reviewReady, !Launch.testing else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard reviewReady else { return }
            guard await store.takeReviewOpportunity() else { return }
            if scenePhase == .active, path.isEmpty, store.undo == nil, store.milestone == nil, store.errorKey == nil {
                requestReview()
            } else {
                await store.restoreReviewOpportunity()
            }
        }
        .onOpenURL { url in inbox.pending = AppLink(url: url) }
        .onChange(of: inbox.pending) { _, _ in openPending() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refresh()
        }
        .alert(L.t("error.title"), isPresented: Binding(get: { store.errorKey != nil }, set: { shown in
            if !shown { store.errorKey = nil }
        })) {
            Button(L.t("action.ok")) { store.errorKey = nil }
            if !store.loaded {
                Button(L.t("action.retry")) { Task { await store.start() } }
            }
        } message: {
            Text(L.t(store.errorKey ?? "error.save"))
        }
    }

    private func navigate(_ route: Route) { path.append(route) }

    private func openPending() {
        guard store.loaded, let route = inbox.pending else { return }
        inbox.pending = nil
        switch route {
        case .home: path = []
        case .birthday: path = [.birthday]
        case .create: path = [.create]
        case .offer(let id): path = store.state.entries.contains(where: { $0.id == id }) ? [.detail(id)] : []
        case .due(let day):
            let hasEvents = ReminderPlan.events(state: store.state, on: store.today)
                .contains { $0.alertDays.contains(day) }
            path = hasEvents ? [.due(day)] : []
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .starter: StarterPage()
        case .create: OfferEditor(initial: OfferEntry(year: store.year, merchant: OfferValue(name: "")), new: true)
        case .detail(let id): OfferDetail(id: id, open: navigate)
        case .edit(let id):
            if let row = store.state.entries.first(where: { $0.id == id }) {
                OfferEditor(initial: row, new: false)
            }
        case .birthday: BirthdayPage()
        case .stats: StatsPage(open: navigate)
        case .importCode: ImportPage()
        case .history: HistoryPage(open: navigate)
        case .cycle(let year): CyclePage(year: year, open: navigate, reuse: {
            Task {
                if await store.change(core: false, { $0.reuse(from: year, on: store.today) }) { path = [] }
            }
        })
        case .past: PastPage(open: navigate)
        case .due(let day): DuePage(day: day, open: navigate)
        }
    }
}
