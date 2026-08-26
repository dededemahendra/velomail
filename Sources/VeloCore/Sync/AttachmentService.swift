import Foundation

public enum AttachmentError: Error, Equatable {
    /// Neither inline data nor a fetchable id — nothing to get.
    case unavailable
    /// The content was not valid base64url.
    case undecodable
}

/// Gets an attachment's bytes and writes them somewhere safe.
public struct AttachmentService: Sendable {
    private let source: GmailReading

    public init(source: GmailReading) {
        self.source = source
    }

    /// The attachment's content: already here if inline, fetched otherwise.
    public func data(for attachment: MailAttachment) async throws -> Data {
        let encoded: String
        if let inline = attachment.inlineData {
            encoded = inline
        } else if let id = attachment.attachmentID {
            encoded = try await source.getAttachment(messageID: attachment.messageID,
                                                     attachmentID: id)
        } else {
            throw AttachmentError.unavailable
        }

        guard let data = Self.decodeBase64URL(encoded) else { throw AttachmentError.undecodable }
        return data
    }

    /// Writes the attachment into `directory`, returning where it landed.
    ///
    /// The name is derived, never trusted — see `safeName`.
    @discardableResult
    public func save(_ attachment: MailAttachment, to directory: URL) async throws -> URL {
        let bytes = try await data(for: attachment)
        let destination = Self.uniqueURL(for: Self.safeName(attachment.filename), in: directory)
        try bytes.write(to: destination)
        return destination
    }

    // MARK: - Filenames are hostile input

    /// Reduces a filename from a stranger to a single, harmless component.
    ///
    /// `../../.ssh/authorized_keys` is a perfectly valid string in a MIME
    /// header. Taking only the last path component and rejecting traversal
    /// segments is what keeps a save inside the directory the user picked.
    static func safeName(_ raw: String) -> String {
        let candidate = raw
            .replacingOccurrences(of: "\\", with: "/")
            .components(separatedBy: "/")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // "." and ".." survive the split above and are not filenames.
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else { return "attachment" }
        return candidate
    }

    /// Never overwrites: a name already in use gets a number, the way a browser
    /// download does.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    /// Gmail's URL-safe base64 (RFC 4648 §5), tolerating missing padding.
    static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
