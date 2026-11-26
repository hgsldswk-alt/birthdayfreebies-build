import Foundation

struct PortableOffer: Codable, Equatable, Sendable {
    var name: String
    var gift: String
    var signup: Requirement
    var signupOffset: Int?
    var opensOffset: Int?
    var endsOffset: Int?

    init(_ entry: OfferEntry) {
        name = entry.merchant.name
        gift = entry.merchant.gift
        signup = entry.signup
        signupOffset = entry.signupBy?.offset
        opensOffset = entry.opens?.offset
        endsOffset = entry.ends?.offset
    }

    var key: OfferKey { OfferKey(name: name, gift: gift, location: "") }

    var valid: Bool {
        guard !key.name.isEmpty, Self.validField(name), Self.validField(gift),
              [signupOffset, opensOffset, endsOffset].compactMap({ $0 }).allSatisfy({ (-366...366).contains($0) })
        else { return false }
        if let opensOffset, let endsOffset { return opensOffset <= endsOffset }
        return true
    }

    private static func validField(_ value: String) -> Bool {
        value.count <= 80 && value.utf8.count <= 320 &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    func entry(in year: Int) -> OfferEntry {
        OfferEntry(year: year, merchant: OfferValue(name: name, gift: gift), signup: signup,
                   signupBy: signupOffset.map { .relative($0) }, opens: opensOffset.map { .relative($0) },
                   ends: endsOffset.map { .relative($0) })
    }
}

enum ShareCode {
    static let byteLimit = 8192
    static let rowLimit = 50
    private static let prefix = "BFC1:"

    private struct Payload: Codable {
        let v: Int
        let offers: [PortableOffer]
    }

    enum Failure: Error { case malformed, limit, empty }

    static func encode(_ entries: [OfferEntry]) throws -> String {
        let offers = entries.filter { !$0.archived }.map(PortableOffer.init)
        guard !offers.isEmpty else { throw Failure.empty }
        guard offers.count <= rowLimit else { throw Failure.limit }
        guard offers.allSatisfy(\.valid) else { throw Failure.malformed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Payload(v: 1, offers: offers))
        let code = prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard code.utf8.count <= byteLimit else { throw Failure.limit }
        return code
    }

    static func decode(_ input: String) throws -> [PortableOffer] {
        guard input.utf8.count <= byteLimit + 16 else { throw Failure.limit }
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= byteLimit else { throw Failure.limit }
        guard code.hasPrefix(prefix) else { throw Failure.malformed }
        let encoded = code.dropFirst(prefix.count)
        guard !encoded.isEmpty, encoded.count % 4 != 1,
              encoded.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw Failure.malformed }
        let base = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base + String(repeating: "=", count: (4 - base.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { throw Failure.malformed }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.v == 1, payload.offers.allSatisfy(\.valid) else { throw Failure.malformed }
        guard !payload.offers.isEmpty else { throw Failure.empty }
        guard payload.offers.count <= rowLimit else { throw Failure.limit }
        return payload.offers
    }

    static func preview(_ offers: [PortableOffer], existing: [OfferEntry]) -> [ImportRow] {
        let local = Set(existing.map { $0.merchant.portableKey })
        let counts = Dictionary(grouping: offers, by: \.key).mapValues(\.count)
        return offers.enumerated().map { index, offer in
            let conflict: ImportRow.Conflict? = local.contains(offer.key) ? .existing :
                (counts[offer.key, default: 0] > 1 ? .ambiguous : nil)
            return ImportRow(id: index, offer: offer, conflict: conflict)
        }
    }
}

struct ImportRow: Identifiable {
    enum Conflict: String { case existing, ambiguous }
    let id: Int
    let offer: PortableOffer
    let conflict: Conflict?
}
