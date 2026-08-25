import Foundation

/// One way off a mailing list, as the sender declared it in `List-Unsubscribe`.
public enum UnsubscribeLink: Equatable, Sendable {
    case mailto(address: String, subject: String?, body: String?)
    case web(URL)
}

/// Reading RFC 2369's `List-Unsubscribe` and turning it into something the app
/// can act on.
///
/// The mailto is preferred over the web link: it is a channel the sender
/// declared, it works without a browser, and it goes out through the existing
/// outbound queue — so it is durable across a restart, retried with backoff, and
/// cancellable for ten seconds with `Cmd+Z` exactly like any other send.
///
/// RFC 8058 one-click POST is deliberately not implemented. It is an
/// unauthenticated HTTP write to an arbitrary URL taken from untrusted mail, and
/// the mailto path already reaches the same result through machinery that can be
/// undone.
public enum Unsubscribe {

    /// Every usable link in the header, in the order the sender wrote them.
    ///
    /// Tolerant, because real headers are not: angle brackets are optional,
    /// whitespace and newlines fall anywhere, and an unrecognised scheme is
    /// skipped rather than failing the whole header — one bad entry must not
    /// cost the user the good one beside it.
    public static func links(in header: String) -> [UnsubscribeLink] {
        candidates(in: header).compactMap(link(from:))
    }

    /// The first mailto, else the first web link.
    public static func preferred(in header: String) -> UnsubscribeLink? {
        let all = links(in: header)
        return all.first { if case .mailto = $0 { return true } else { return false } } ?? all.first
    }

    /// The mail that performs a mailto unsubscribe. Nil for a web link, because
    /// completing a form on the sender's site is not something a mail client can
    /// do on the user's behalf.
    public static func draft(for link: UnsubscribeLink) -> Draft? {
        guard case let .mailto(address, subject, body) = link else { return nil }
        // Some list servers match on the exact subject they asked for, so the
        // header's wording wins whenever it gave one.
        return Draft(to: [address],
                     subject: subject ?? "Unsubscribe",
                     bodyText: body ?? "Unsubscribe")
    }

    // MARK: - Internals

    /// Splits the header into individual link strings. Angle-bracketed groups
    /// when there are any, else comma-separated pieces.
    private static func candidates(in header: String) -> [String] {
        var bracketed: [String] = []
        var current: String?
        for character in header {
            switch character {
            case "<": current = ""
            case ">":
                if let value = current { bracketed.append(value) }
                current = nil
            default: current?.append(character)
            }
        }
        guard bracketed.isEmpty else { return bracketed.map(trimmed) }
        return header.split(separator: ",").map { trimmed(String($0)) }
    }

    private static func link(from candidate: String) -> UnsubscribeLink? {
        let value = trimmed(candidate)
        let scheme = value.prefix(while: { $0 != ":" }).lowercased()
        switch scheme {
        case "mailto":
            return mailto(value.dropFirst("mailto:".count))
        case "http", "https":
            return URL(string: value).map(UnsubscribeLink.web)
        default:
            return nil
        }
    }

    private static func mailto(_ rest: Substring) -> UnsubscribeLink? {
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address = trimmed(String(parts[0]))
        guard !address.isEmpty else { return nil }

        var subject: String?
        var body: String?
        for pair in parts.count > 1 ? parts[1].split(separator: "&") : [] {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            // A mailto query is not a form encoding (RFC 6068), so `+` stays a
            // literal plus rather than becoming a space.
            let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            switch kv[0].lowercased() {
            case "subject": subject = value
            case "body": body = value
            default: break
            }
        }
        return .mailto(address: address, subject: subject, body: body)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
