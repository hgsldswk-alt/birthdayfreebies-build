import SwiftUI

struct ActionButton: View {
    enum Kind { case plain, outline, primary }

    let title: String
    let id: String
    var kind: Kind
    var symbol: String?
    var action: () -> Void

    init(_ title: String, id: String, kind: Kind = .plain, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if kind == .primary {
            PrimaryButton(title, id: id, symbol: symbol ?? "checkmark", action: action)
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, kind == .plain ? 6 : 12)
                .padding(.vertical, 6)
                .frame(minWidth: 44, maxWidth: kind == .plain ? nil : .infinity, minHeight: 44)
                .foregroundStyle(Palette.deep)
                .background(kind == .outline ? Palette.tint : .clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier(id)
        }
    }
}

struct Page<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: 570)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DesignStyle.background.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var overline: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if let overline { CaptionLabel(title: overline) }
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing
        }
    }
}

struct BackHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String? = nil
    var overline: String? = nil
    var cancel = false

    var body: some View {
        PageHeader(title: title, subtitle: subtitle, overline: overline) {
            ActionButton(L.t(cancel ? "action.cancel" : "action.back"), id: "nav.back",
                         symbol: cancel ? "xmark" : "chevron.left") { dismiss() }
        }
    }
}

struct CaptionLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.caption2.weight(.heavy)).textCase(.uppercase)
            .tracking(0.7).foregroundStyle(Palette.deep)
    }
}

struct Panel<Content: View>: View {
    var padded = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: padded ? 8 : 0) { content }
            .padding(padded ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: DesignStyle.card)
            .overlay { DesignStyle.card.strokeBorder(Palette.line.opacity(0.45)).allowsHitTesting(false) }
            .shadow(color: DesignStyle.shadow, radius: 12, x: 0, y: 4)
    }
}

struct Notice: View {
    let title: String
    var body: some View {
        Text(title).font(.footnote).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white, in: DesignStyle.card)
            .overlay { DesignStyle.card.strokeBorder(Palette.line.opacity(0.55)).allowsHitTesting(false) }
            .shadow(color: DesignStyle.shadow, radius: 12, x: 0, y: 4)
    }
}

struct SectionTitle: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Palette.muted).accessibilityAddTraits(.isHeader)
            if let count { Text(count.formatted()).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted) }
        }
    }
}

struct EmptyReturn: View {
    @Environment(\.dismiss) private var dismiss
    let message: String
    let id: String

    var body: some View {
        EmptyIllustration(message: message, actionTitle: L.t("action.back"), actionSymbol: "chevron.left", id: id) {
            dismiss()
        }
    }
}

struct ChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let id: String
    var symbol = "checklist"
    var tone: DesignTone = .mint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconRow(title: title, detail: detail, symbol: symbol, tone: tone) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 5).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line) }
    }
}
