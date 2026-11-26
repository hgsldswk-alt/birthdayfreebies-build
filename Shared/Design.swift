import SwiftUI

enum DesignStyle {
    static let background = Color(red: 247/255, green: 245/255, blue: 240/255)
    static let mint = Color(red: 212/255, green: 239/255, blue: 225/255)
    static let butter = Color(red: 242/255, green: 210/255, blue: 122/255)
    static let coral = Color(red: 232/255, green: 131/255, blue: 107/255)
    static let blue = Color(red: 143/255, green: 179/255, blue: 217/255)
    static let shadow = Color.black.opacity(0.07)
    static let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
    static let giftGradient = LinearGradient(
        stops: [
            .init(color: Palette.accent, location: 0),
            .init(color: Palette.accent, location: 0.42),
            .init(color: Color(red: 47/255, green: 129/255, blue: 105/255), location: 0.62),
            .init(color: mint, location: 1)
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

enum DesignTone {
    case mint, butter, coral, blue, neutral

    var color: Color {
        switch self {
        case .mint: return DesignStyle.mint
        case .butter: return DesignStyle.butter
        case .coral: return DesignStyle.coral
        case .blue: return DesignStyle.blue
        case .neutral: return Palette.marker
        }
    }

    var ink: Color { self == .mint ? Palette.deep : Palette.ink }
}

struct HeroCard<Content: View>: View {
    var prominent = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if prominent {
                    DesignStyle.card.fill(DesignStyle.giftGradient)
                } else {
                    DesignStyle.card.fill(
                        LinearGradient(colors: [.white, Palette.tint], startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                }
            }
            .overlay { DesignStyle.card.strokeBorder(Palette.line.opacity(0.45)).allowsHitTesting(false) }
            .shadow(color: DesignStyle.shadow, radius: 12, x: 0, y: 4)
    }
}

struct DesignIcon: View {
    let symbol: String
    let tone: DesignTone
    var circle = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: 38, height: 38)
            .background {
                if circle { Circle().fill(tone.color) }
                else { RoundedRectangle(cornerRadius: 11).fill(tone.color) }
            }
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    let title: String
    let symbol: String
    let tone: DesignTone
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DesignIcon(symbol: symbol, tone: tone, circle: true)
                Text(title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(.white, in: DesignStyle.card)
            .overlay { DesignStyle.card.strokeBorder(Palette.line.opacity(0.45)).allowsHitTesting(false) }
            .shadow(color: DesignStyle.shadow, radius: 12, x: 0, y: 4)
            .contentShape(DesignStyle.card)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id)
    }
}

struct IconRow<Trailing: View>: View {
    let title: String
    let detail: String
    let symbol: String
    let tone: DesignTone
    let heading: Bool
    let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    init(title: String, detail: String = "", symbol: String, tone: DesignTone, heading: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        self.heading = heading
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            DesignIcon(symbol: symbol, tone: tone)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(heading ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(heading ? Palette.muted : Palette.ink)
                        .accessibilityAddTraits(heading ? .isHeader : [])
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Palette.muted) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension IconRow where Trailing == EmptyView {
    init(title: String, detail: String = "", symbol: String, tone: DesignTone, heading: Bool = false) {
        self.init(title: title, detail: detail, symbol: symbol, tone: tone, heading: heading) { EmptyView() }
    }
}

struct StatusPill: View {
    let title: String
    var tone: DesignTone = .mint

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tone.color, in: Capsule())
    }
}

struct ProgressRing: View {
    let count: Int
    let total: Int
    @ScaledMetric(relativeTo: .title3) private var diameter: CGFloat = 74

    init(count: Int, total: Int) {
        self.count = count
        self.total = total
    }

    private var progress: Double { min(1, max(0, Double(count) / Double(max(1, total)))) }

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.tint, lineWidth: 6)
            if progress > 0 {
                let arc = Circle().inset(by: 4).trim(from: 0, to: CGFloat(progress))
                arc.stroke(Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .overlay { arc.stroke(DesignStyle.butter, style: StrokeStyle(lineWidth: 4, lineCap: .round)) }
                    .rotationEffect(.degrees(-90))
            }
            Text(L.f("stats.fraction", count, total))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.deep)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 8)
        }
        .frame(width: min(diameter, 96), height: min(diameter, 96))
        .background(.white, in: Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("stage.claimed"))
        .accessibilityValue(L.f("stats.fraction", count, total))
    }
}

struct GiftIllustration: View {
    var size: CGFloat = 76
    var onGreen = false

    var body: some View {
        ZStack {
            Circle().fill(onGreen ? Color.white.opacity(0.18) : DesignStyle.mint)
                .frame(width: size * 0.79, height: size * 0.79)
            Image(systemName: "gift.fill")
                .font(.system(size: size * 0.49, weight: .medium))
                .foregroundStyle(onGreen ? .white : Palette.deep)
                .rotationEffect(.degrees(-12))
            DesignIcon(symbol: "sparkles", tone: .butter, circle: true)
                .scaleEffect(size * 0.30 / 38)
                .offset(x: size * 0.34, y: -size * 0.31)
            DesignIcon(symbol: "heart.fill", tone: .coral, circle: true)
                .scaleEffect(size * 0.23 / 38)
                .offset(x: -size * 0.35, y: size * 0.27)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct EmptyIllustration: View {
    let message: String
    let actionTitle: String
    let actionSymbol: String
    let id: String
    let action: () -> Void

    var body: some View {
        HeroCard {
            VStack(spacing: 12) {
                GiftIllustration(size: 88)
                Text(message).font(.subheadline).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(actionTitle, id: id, symbol: actionSymbol, action: action)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let id: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, id: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.id = id
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
    }
}

enum OfferArtwork {
    case drink, beauty, dessert, books, general

    init(name: String, gift: String, starterID: String? = nil) {
        switch starterID {
        case "starbucks":
            self = .drink
            return
        case "sephora", "ulta":
            self = .beauty
            return
        case "krispy", "bundt":
            self = .dessert
            return
        default: break
        }
        let text = (name + " " + gift).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                             locale: Locale(identifier: "en_US_POSIX"))
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: ["beauty", "makeup", "cosmetics", "skincare", "lipstick"])
            || ["美妆", "美妝", "护肤", "護膚", "彩妆", "彩妝", "口红", "口紅"].contains(where: { text.contains($0) }) {
            self = .beauty
        } else if !words.isDisjoint(with: ["book", "books", "bookstore", "bookmark", "bookshop"])
            || ["书店", "書店", "书签", "書籤", "书籍", "書籍"].contains(where: { text.contains($0) }) {
            self = .books
        } else if !words.isDisjoint(with: ["bakery", "cake", "pastry", "dessert", "donut", "doughnut", "cookie", "sweet"])
            || ["蛋糕", "甜点", "甜點", "甜品", "糕点", "糕點", "点心", "點心", "烘焙", "冰淇淋"]
                .contains(where: { text.contains($0) }) {
            self = .dessert
        } else if !words.isDisjoint(with: ["tea", "coffee", "cafe", "drink", "latte", "beverage", "smoothie"])
            || ["咖啡", "饮品", "飲品", "奶茶", "饮料", "飲料"].contains(where: { text.contains($0) }) {
            self = .drink
        } else {
            self = .general
        }
    }

    init(_ entry: OfferEntry) {
        self.init(name: entry.merchant.name, gift: entry.merchant.gift, starterID: entry.starterID)
    }

    var symbol: String {
        switch self {
        case .drink: return "cup.and.saucer.fill"
        case .beauty: return "sparkles"
        case .dessert: return "birthday.cake.fill"
        case .books: return "book.fill"
        case .general: return "gift.fill"
        }
    }

    var tone: DesignTone {
        switch self {
        case .drink: return .mint
        case .beauty: return .coral
        case .dessert: return .butter
        case .books: return .blue
        case .general: return .neutral
        }
    }
}

extension OfferStage {
    func pillTone(urgent: Bool = false) -> DesignTone {
        switch self {
        case .signup: return .butter
        case .waiting: return .blue
        case .ready: return urgent ? .coral : .mint
        case .claimed: return .mint
        case .past: return .neutral
        }
    }
}
