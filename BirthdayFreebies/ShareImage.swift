import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum CardContent: Equatable {
    case stats(claimed: Int, free: Int)
    case milestone(Int)

    var number: Int {
        switch self {
        case .stats(let claimed, let free): return free > 0 ? free : claimed
        case .milestone(let value): return value
        }
    }

    var title: String {
        switch self {
        case .stats(_, let free): return L.t(free > 0 ? "share.free_title" : "share.claimed_title")
        case .milestone(let value): return L.t(value == 1 ? "milestone.first" : "milestone.tenth")
        }
    }

    var caption: String {
        switch self {
        case .stats(_, let free): return L.f(free > 0 ? "share.free_caption" : "share.claimed_caption", number) + "\n" + ShareImage.hashtags
        case .milestone: return title + "\n" + ShareImage.hashtags
        }
    }
}

enum ShareImage {
    static let hashtags = "#birthdayfreebies #birthdayrewards"

    static func downloadURL(appID: String? = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String) -> URL? {
        guard let id = appID, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }

    static func qr(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    @MainActor static func png(_ content: CardContent, url: URL? = downloadURL()) -> Data? {
        let renderer = ImageRenderer(content: CardArt(content: content, qr: url.flatMap { qr(for: $0) })
            .frame(width: 360, height: 450)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

struct CardArt: View {
    let content: CardContent
    let qr: CGImage?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 360, geometry.size.height / 450)
            layout
                .frame(width: 360, height: 450)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.f("share.preview_label", content.number, content.title))
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("share.header")).font(.system(size: 13, weight: .heavy)).textCase(.uppercase)
                .tracking(1.1).foregroundStyle(Palette.deep)
            HStack(alignment: .top) {
                Text(content.number.formatted()).font(.system(size: 98, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.45).lineLimit(1).foregroundStyle(Palette.deep)
                    .accessibilityHidden(true)
                Spacer()
                GiftIllustration(size: 96)
                    .padding(.top, 10)
            }
            Text(content.title).font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TicketPerforation().frame(height: 10).accessibilityHidden(true)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShareImage.hashtags.replacingOccurrences(of: " ", with: "\n"))
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.deep)
                    Text(L.t(qr == nil ? "share.qr_placeholder" : "share.download"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Group {
                    if let qr {
                        Image(decorative: qr, scale: 1).interpolation(.none).resizable()
                    } else {
                        Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 82, height: 82).padding(9).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            DesignStyle.card.fill(LinearGradient(colors: [.white, Palette.tint],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { DesignStyle.card.strokeBorder(DesignStyle.giftGradient, lineWidth: 4) }
    }
}

private struct TicketPerforation: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<28, id: \.self) { _ in Capsule().fill(Palette.line).frame(height: 2) }
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
