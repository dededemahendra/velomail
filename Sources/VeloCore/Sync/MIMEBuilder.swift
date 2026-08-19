import Foundation

/// Serializes a `Draft` into an RFC 5322 message and into the base64url `raw`
/// form that `users.messages.send` expects.
///
/// `date`, `messageID` and `boundary` are injected rather than generated here so
/// the output is a pure function of its inputs and tests can assert exact bytes.
public enum MIMEBuilder {
    /// The RFC 5322 message: headers, a blank line, then the body.
    public static func serialize(_ draft: Draft, from: String, messageID: String,
                                 date: Date, boundary: String) -> String {
        var headers: [String] = [
            "From: \(from)",
            "To: \(draft.to.joined(separator: ", "))",
        ]
        if !draft.cc.isEmpty { headers.append("Cc: \(draft.cc.joined(separator: ", "))") }
        if !draft.bcc.isEmpty { headers.append("Bcc: \(draft.bcc.joined(separator: ", "))") }
        headers.append("Subject: \(encodedWordIfNeeded(draft.subject))")
        headers.append("Date: \(rfc5322Date(date))")
        headers.append("Message-ID: \(messageID)")
        if let inReplyTo = draft.inReplyTo { headers.append("In-Reply-To: \(inReplyTo)") }
        if !draft.references.isEmpty {
            headers.append("References: \(draft.references.joined(separator: " "))")
        }
        headers.append("MIME-Version: 1.0")

        let (contentHeaders, body) = content(of: draft, boundary: boundary)
        headers.append(contentsOf: contentHeaders)

        return (headers + ["", body]).joined(separator: crlf)
    }

    /// The serialized message in base64url with padding stripped, ready for the
    /// `raw` field of a send request.
    public static func raw(_ draft: Draft, from: String, messageID: String,
                           date: Date, boundary: String) -> String {
        base64URL(Data(serialize(draft, from: from, messageID: messageID,
                                 date: date, boundary: boundary).utf8))
    }

    // MARK: - Body

    /// Content headers plus the body. A draft with HTML becomes a
    /// `multipart/alternative` whose plain-text part comes first, per RFC 2046:
    /// the least-capable rendering goes earliest so simple clients stop there.
    private static func content(of draft: Draft, boundary: String) -> (headers: [String], body: String) {
        guard let html = draft.bodyHTML else {
            return (["Content-Type: text/plain; charset=\"UTF-8\"",
                     "Content-Transfer-Encoding: base64"],
                    base64Body(draft.bodyText))
        }

        let parts = [
            ["--\(boundary)",
             "Content-Type: text/plain; charset=\"UTF-8\"",
             "Content-Transfer-Encoding: base64",
             "",
             base64Body(draft.bodyText)].joined(separator: crlf),
            ["--\(boundary)",
             "Content-Type: text/html; charset=\"UTF-8\"",
             "Content-Transfer-Encoding: base64",
             "",
             base64Body(html)].joined(separator: crlf),
            "--\(boundary)--",
        ]
        return (["Content-Type: multipart/alternative; boundary=\"\(boundary)\""],
                parts.joined(separator: crlf))
    }

    // MARK: - Encoding

    private static let crlf = "\r\n"

    /// Base64 wrapped at 76 columns, the RFC 2045 limit. Wrapping matters: an
    /// unwrapped body can exceed the 998-octet line cap that RFC 5322 imposes,
    /// which some MTAs enforce by rewriting or rejecting the message.
    private static func base64Body(_ string: String) -> String {
        let encoded = Data(string.utf8).base64EncodedString()
        return stride(from: 0, to: encoded.count, by: 76).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: min(76, encoded.count - offset))
            return String(encoded[start..<end])
        }.joined(separator: crlf)
    }

    /// Wraps a header value as an RFC 2047 base64 encoded-word when it is not
    /// pure ASCII. Header fields are ASCII-only, so a raw "Café" is invalid.
    private static func encodedWordIfNeeded(_ value: String) -> String {
        guard value.contains(where: { !$0.isASCII }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Fixed-format RFC 5322 date in UTC. The POSIX locale is mandatory: a
    /// device locale would localize the day and month names into something no
    /// mail parser accepts.
    private static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
