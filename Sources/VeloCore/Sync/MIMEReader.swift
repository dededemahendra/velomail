import Foundation

/// Turns an RFC 5322 message back into a `Draft`.
///
/// The inverse of `MIMEBuilder`, and deliberately forgiving: a draft that
/// cannot be parsed is skipped rather than thrown, because one malformed
/// message on the account should not stop the rest arriving.
public enum MIMEReader {
    public static func draft(fromBase64URL raw: String) -> Draft? {
        var padded = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return draft(from: text)
    }

    public static func draft(from message: String) -> Draft? {
        let normalised = message.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalised.components(separatedBy: "\n\n")
        guard let head = parts.first else { return nil }
        let body = parts.dropFirst().joined(separator: "\n\n")

        var headers: [String: String] = [:]
        var lastKey: String?
        for line in head.components(separatedBy: "\n") {
            // A header wrapped onto the next line begins with whitespace.
            if line.first == " " || line.first == "\t", let key = lastKey {
                headers[key, default: ""] += line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].lowercased()
            headers[key] = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            lastKey = key
        }

        return Draft(to: addresses(headers["to"]),
                     cc: addresses(headers["cc"]),
                     bcc: addresses(headers["bcc"]),
                     subject: headers["subject"] ?? "",
                     bodyText: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func addresses(_ value: String?) -> [String] {
        (value ?? "").components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
