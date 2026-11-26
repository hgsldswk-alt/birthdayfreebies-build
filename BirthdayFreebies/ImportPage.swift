import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportPage: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var selected = Set<Int>()
    @State private var pickFile = false
    @State private var fileFailure = false
    @FocusState private var focused: Bool

    private var preview: [ImportRow] {
        let offers = (try? ShareCode.decode(code)) ?? []
        return ShareCode.preview(offers, existing: store.state.rows(in: store.year))
    }

    private var newOffers: [ImportRow] { preview.filter { $0.conflict == nil && !selected.contains($0.id) } }

    var body: some View {
        Page {
            BackHeader(title: L.t("import.title"), subtitle: L.t("import.subtitle"), cancel: true)
            Panel {
                SectionTitle(title: L.t("import.code"))
                TextField(L.t("import.placeholder"), text: $code, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4)
                    .focused($focused).fieldStyle().accessibilityIdentifier("import.code")
                HStack {
                    ActionButton(L.t("import.paste"), id: "import.paste", kind: .outline, symbol: "clipboard") { paste() }
                    ActionButton(L.t("import.file"), id: "import.file", kind: .outline, symbol: "doc") {
                        focused = false; pickFile = true
                    }
                }
            }
            if fileFailure { Notice(title: L.t("import.file_error")) }
            if preview.isEmpty && !code.isEmpty {
                Notice(title: L.t("import.invalid")).accessibilityIdentifier("import.invalid")
            }
            if !preview.isEmpty { previewPanel }
            PrimaryButton(newOffers.isEmpty ? L.t("import.add") : L.f("import.add_count", newOffers.count),
                          id: "import.add", symbol: "plus") { Task { await add() } }
                .disabled(newOffers.isEmpty || store.saving)
        }
        .onChange(of: code) { _, _ in selected = [] }
        .fileImporter(isPresented: $pickFile, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url): Task { await loadFile(url) }
            case .failure: fileFailure = true
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: L.f("import.preview", newOffers.count))
            Panel(padded: false) {
                ForEach(preview) { row in
                    let artwork = OfferArtwork(name: row.offer.name, gift: row.offer.gift)
                    if row.id != preview.first?.id { Divider() }
                    ChoiceRow(title: row.offer.name,
                              detail: row.conflict.map { L.t("import." + $0.rawValue) } ??
                                [row.offer.gift, row.offer.signup.title].filter { !$0.isEmpty }.joined(separator: " · "),
                              selected: row.conflict == nil && !selected.contains(row.id),
                              id: "import.row.\(row.id)", symbol: artwork.symbol, tone: artwork.tone) {
                        if selected.contains(row.id) { selected.remove(row.id) }
                        else { selected.insert(row.id) }
                    }
                    .disabled(row.conflict != nil)
                }
            }
            if preview.contains(where: { $0.conflict != nil }) {
                Notice(title: L.t("import.conflicts"))
            }
        }
    }

    private func paste() {
        focused = false
        fileFailure = false
        let input = Launch.testing ? ProcessInfo.processInfo.environment["BFC_UI_CODE"] : UIPasteboard.general.string
        if let input { code = input }
    }

    private func loadFile(_ url: URL) async {
        do {
            code = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: ShareCode.byteLimit + 17) ?? Data()
                guard data.count <= ShareCode.byteLimit + 16, let code = String(data: data, encoding: .utf8)
                else { throw ShareCode.Failure.limit }
                return code
            }.value
            fileFailure = false
        } catch {
            fileFailure = true
        }
    }

    private func add() async {
        let year = store.year
        let offers = newOffers.map { $0.offer.entry(in: year) }
        if await store.change(core: false, { $0.add(offers, in: year, portable: true) }) { dismiss() }
    }
}
