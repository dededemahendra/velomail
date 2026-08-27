import Foundation
import SwiftUI
import VeloCore

/// Saving an attachment, and what to tell the user about it.
@MainActor
public final class AttachmentViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case saving(String)
        case saved(URL)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    private let service: AttachmentService
    private let downloads: URL

    public init(service: AttachmentService, downloads: URL = AttachmentViewModel.defaultDownloads) {
        self.service = service
        self.downloads = downloads
    }

    nonisolated public static var defaultDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    public func save(_ attachment: MailAttachment) async {
        state = .saving(attachment.filename)
        do {
            state = .saved(try await service.save(attachment, to: downloads))
        } catch {
            state = .failed(Self.describe(error, filename: attachment.filename))
        }
    }

    public func dismiss() { state = .idle }

    /// Opens an attachment in Quick Look without keeping it.
    ///
    /// Saved to a temporary directory rather than Downloads: looking at
    /// something is not the same as wanting a copy of it, and a Downloads
    /// folder that fills up with everything glanced at is its own annoyance.
    public func preview(_ attachment: MailAttachment) async {
        state = .saving(attachment.filename)
        do {
            let url = try await service.save(attachment, to: AttachmentViewModel.previewFolder)
            state = .idle
            NSWorkspace.shared.open(url)
        } catch {
            state = .failed(Self.describe(error, filename: attachment.filename))
        }
    }

    /// A file promise for dragging an attachment out.
    ///
    /// Written to the same temporary folder as a preview: dropping it on the
    /// desktop copies it, and nothing is left in Downloads for a drag that was
    /// abandoned halfway.
    nonisolated public func provider(for attachment: MailAttachment) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = attachment.filename
        let service = self.service
        provider.registerFileRepresentation(forTypeIdentifier: "public.data",
                                            fileOptions: [], visibility: .all) { completion in
            Task {
                do {
                    let url = try await service.save(attachment,
                                                     to: AttachmentViewModel.previewFolder)
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    /// Cleared by the system, and per-launch so two runs cannot collide over
    /// a name.
    nonisolated static let previewFolder: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VeloMail-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Reveals a saved file in Finder.
    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Display

    /// A size, or nothing at all when Gmail did not give one — "0 bytes" beside
    /// a real file reads as a bug.
    nonisolated public static func formattedSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    nonisolated public static func symbol(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case let type where type.hasPrefix("image/"): return "photo"
        case let type where type.hasPrefix("video/"): return "film"
        case let type where type.hasPrefix("audio/"): return "waveform"
        case "application/pdf": return "doc.richtext"
        case let type where type.contains("zip") || type.contains("compressed"): return "doc.zipper"
        case let type where type.hasPrefix("text/"): return "doc.text"
        default: return "paperclip"
        }
    }

    nonisolated static func describe(_ error: Error, filename: String) -> String {
        switch error {
        case AttachmentError.unavailable:
            return "\(filename) is not available to download."
        case AttachmentError.undecodable:
            return "\(filename) came back unreadable."
        default:
            return "Could not save \(filename)."
        }
    }
}
