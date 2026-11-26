import SwiftUI
import UIKit

struct StatsPage: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var activity: Activity?
    @State private var notice: String?
    @State private var qr: CGImage?
    @State private var exporting = false

    let open: (Route) -> Void

    private struct Activity: Identifiable {
        let id = UUID()
        let items: [Any]
        let folder: URL
    }

    private var rows: [OfferEntry] { store.state.rows(in: store.year) }
    private var claimed: Int { rows.filter { $0.claimed != nil }.count }
    private var free: Int { rows.filter(\.confirmedFree).count }
    private var total: Int { rows.filter { !$0.archived || $0.claimed != nil }.count }
    private var achieved: [Int] {
        (store.state.cycles[store.year]?.milestones ?? []).filter { claimed >= $0 }.sorted()
    }

    var body: some View {
        Page {
            BackHeader(title: L.t("stats.title"), subtitle: L.f("home.year", String(store.year)))
            summary
            CardArt(content: .stats(claimed: claimed, free: free), qr: qr)
                .frame(maxWidth: 228).frame(maxWidth: .infinity)
            PrimaryButton(L.t("share.image"), id: "stats.share", symbol: "square.and.arrow.up") {
                Task { await exportImage(.stats(claimed: claimed, free: free)) }
            }
            .disabled(exporting)
            if let notice {
                Notice(title: L.t(notice)).accessibilityIdentifier(notice == "share.requested" ? "share.requested" : "stats.notice")
            }
            if !achieved.isEmpty { milestones }
            ActionButton(L.t("share.copy"), id: "stats.copy", kind: .outline, symbol: "doc.on.doc") { copyCode() }
            ActionButton(L.t("share.file"), id: "stats.file", kind: .outline, symbol: "doc") { Task { await shareFile() } }
                .disabled(exporting)
        }
        .sheet(item: $activity) { item in
            ActivitySheet(items: item.items)
                .onDisappear { Task.detached { try? FileManager.default.removeItem(at: item.folder) } }
        }
        .task {
            if let url = ShareImage.downloadURL() {
                qr = await Task.detached { ShareImage.qr(for: url) }.value
            }
        }
    }

    private var summary: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        return HeroCard {
            layout {
                ProgressRing(count: claimed, total: total)
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: L.t("stage.claimed"))
                    StatusPill(title: L.f("stats.free_count", free))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ActionButton(L.t("action.history"), id: "stats.history", symbol: "clock.arrow.circlepath") {
                    open(.history)
                }
            }
        }
    }

    private var milestones: some View {
        Panel {
            SectionTitle(title: L.t("milestone.title"))
            ForEach(achieved, id: \.self) { value in
                if value != achieved.first { Divider() }
                IconRow(title: CardContent.milestone(value).title, symbol: "checkmark.seal.fill", tone: .butter) {
                    ActionButton(L.t("action.share"), id: "stats.milestone.\(value)") {
                        Task { await exportImage(.milestone(value)) }
                    }
                    .disabled(exporting)
                }
            }
        }
    }

    private func copyCode() {
        do {
            let code = try ShareCode.encode(rows)
            if !Launch.testing { UIPasteboard.general.string = code }
            notice = "share.copied"
        } catch ShareCode.Failure.empty {
            notice = "share.no_offers"
        } catch {
            notice = "share.code_error"
        }
    }

    private func shareFile() async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            let code = try ShareCode.encode(rows)
            try await share(Data(code.utf8), filename: "birthday-checklist.txt", caption: nil)
        } catch ShareCode.Failure.empty {
            notice = "share.no_offers"
        } catch ShareCode.Failure.limit {
            notice = "share.code_error"
        } catch {
            notice = "share.export_error"
        }
    }

    private func exportImage(_ card: CardContent) async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            guard let data = ShareImage.png(card) else { throw CocoaError(.fileWriteUnknown) }
            try await share(data, filename: "birthday-freebies.png", caption: card.caption)
        } catch {
            notice = "share.export_error"
        }
    }

    private func share(_ data: Data, filename: String, caption: String?) async throws {
        let file = try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let path = folder.appendingPathComponent(filename)
            do {
                try data.write(to: path, options: .atomic)
                return path
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }.value
        let folder = file.deletingLastPathComponent()
        if Launch.testing {
            notice = "share.requested"
            _ = await Task.detached { try? FileManager.default.removeItem(at: folder) }.value
        } else {
            var items: [Any] = [file]
            if let caption { items.append(caption) }
            activity = Activity(items: items, folder: folder)
        }
    }
}
