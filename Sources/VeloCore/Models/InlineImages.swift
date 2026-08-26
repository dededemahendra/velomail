import Foundation

/// Resolves a message body's `cid:` references against its own parts.
///
/// A `cid:` URL means nothing to a web view: it points into the MIME message,
/// which the view never sees. Substituting the bytes as a `data:` URI is what
/// makes a logo in a signature or a picture in a newsletter appear, and it does
/// it without loosening the content rules -- nothing is fetched from anywhere.
public enum InlineImages {
    /// `html` with every resolvable `cid:` reference replaced by its bytes.
    ///
    /// A reference with no matching part is left as it is. Better a broken
    /// image than a wrong one: falling back to the nearest attachment would
    /// show the reader a picture the sender did not send.
    public static func embed(_ html: String, using attachments: [MailAttachment]) -> String {
        guard html.contains("cid:") else { return html }

        var out = html
        for attachment in attachments {
            guard let contentID = attachment.contentID,
                  let data = attachment.inlineData, !data.isEmpty else { continue }
            let uri = "data:\(attachment.mimeType);base64,\(standardBase64(data))"
            for quote in ["\"", "'"] {
                out = out.replacingOccurrences(of: "\(quote)cid:\(contentID)\(quote)",
                                               with: "\(quote)\(uri)\(quote)")
            }
        }
        return out
    }

    /// Gmail hands back base64url; a `data:` URI needs standard base64. The two
    /// differ in exactly the characters binary data is full of.
    private static func standardBase64(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
    }
}
