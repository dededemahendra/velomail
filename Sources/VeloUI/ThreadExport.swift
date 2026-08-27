import Foundation
import VeloCore

/// Writes a thread out as a plain text file.
///
/// The escape hatch for keeping a conversation somewhere this client is not:
/// a record for a project folder, an attachment to something else, a thing to
/// print. Plain text rather than HTML because what people want out of an email
/// thread is the words in order.
enum ThreadExport {
    /// The whole conversation, oldest first, each message under its own header.
    static func plainText(of messages: [Message], now: Date = Date()) -> String {
        messages.map { message in
            var lines = ["From: \(message.sender)"]
            if !message.recipients.isEmpty {
                lines.append("To: \(message.recipients.joined(separator: ", "))")
            }
            if !message.cc.isEmpty {
                lines.append("Cc: \(message.cc.joined(separator: ", "))")
            }
            lines.append("Date: \(stamp.string(from: message.date))")
            lines.append("Subject: \(message.subject)")
            lines.append("")
            lines.append(body(of: message))
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n---\n\n") + "\n"
    }

    /// The message as words, whichever way the sender wrote it.
    private static func body(of message: Message) -> String {
        if let text = message.bodyText,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let html = message.bodyHTML, !html.isEmpty else { return "(no text)" }
        // The same stripper the reply quoter uses, so an exported thread and a
        // quoted one read the same way.
        return QuotedReply.strippedTags(html)
    }

    /// A filename made from the subject, safe on any filesystem.
    ///
    /// Falls back to the thread id: a subjectless thread must still be
    /// saveable, and an empty name would make a dotfile.
    static func fileName(for messages: [Message], threadID: String) -> String {
        let subject = messages.last?.subject ?? ""
        let cleaned = subject
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let stem = cleaned.isEmpty ? threadID : String(cleaned.prefix(60))
            .trimmingCharacters(in: .whitespaces)
        return (stem.isEmpty ? threadID : stem) + ".txt"
    }

    /// Writes it, numbering the name rather than overwriting what is there.
    @discardableResult
    static func write(_ text: String, named name: String,
                      into directory: URL = AttachmentViewModel.defaultDownloads) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(name)
        var attempt = 2
        let stem = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem) \(attempt).txt")
            attempt += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
