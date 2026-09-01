import Foundation

/// A `mailto:` link, taken apart.
///
/// A mail client that hands one of these to the system opens whatever the
/// reader's *default* mail client is, which may not be this one and in any case
/// is a strange thing for a mail client to do. It belongs in the composer that
/// is already in front of them.
///
/// The query is not decoration. An unsubscribe link is routinely
/// `mailto:leave@list?subject=unsubscribe`, and a message sent without that
/// subject does nothing at all.
public struct MailtoLink: Equatable, Sendable {
    public let to: [String]
    public let cc: [String]
    public let subject: String?
    public let body: String?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "mailto" else { return nil }

        // `URLComponents` puts everything between the scheme and the query in
        // `path` for a mailto, which is where the recipients are.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        to = MailtoLink.addresses(in: components?.path ?? "")

        let items = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            // Case-insensitive: real links use `Subject` and `subject` alike.
            //
            // `+` is left alone. Turning it into a space is the
            // form-urlencoded convention, and it applies to the raw query
            // *before* percent-decoding -- `queryItems` has already decoded, so
            // doing it here eats a literal plus that arrived as `%2B`. A
            // subject of "invoice + receipt" came out as "invoice   receipt".
            // RFC 6068 spells a space in a mailto as `%20`.
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        cc = MailtoLink.addresses(in: value("cc") ?? "")
        subject = value("subject")
        body = value("body")
    }

    /// Comma-separated, trimmed, and without the empties that a trailing or
    /// doubled comma leaves behind.
    private static func addresses(in raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
