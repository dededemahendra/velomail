import Foundation
import VeloCore

/// The line under a sender's name in an opened message.
///
/// It used to be the raw `From` header followed by every recipient, so a
/// message from Asana read "Asana" and then "Asana <no-reply@asana.com>"
/// underneath -- the name twice -- and then printed the reader's own address
/// back at them.
enum MessageAddressing {
    /// The sender's bare address. The name is already in bold above it, and
    /// saying it twice is not detail, it is repetition.
    static func address(of sender: String) -> String {
        let bare = Draft.normalizedAddress(sender)
        // A sender who gave no address at all: better their raw header than an
        // empty line.
        return bare.isEmpty ? sender : bare
    }

    /// Who it went to, in words, from the reader's point of view.
    ///
    /// "to me" rather than the reader's own address: they know it, and reading
    /// your own address back is the sort of thing that makes software feel
    /// like a form.
    static func recipients(to: [String], cc: [String] = [],
                           identity: String) -> String? {
        let mine = Draft.normalizedAddress(identity)
        // Both forms kept: the comparison needs the bare address and the words
        // need the name, and normalising first threw the name away.
        let all = (to + cc)
            .map { (header: $0, address: Draft.normalizedAddress($0)) }
            .filter { !$0.address.isEmpty }
        guard !all.isEmpty else { return nil }

        let includesMe = all.contains { $0.address == mine }
        let others = all.filter { $0.address != mine }

        switch (includesMe, others.count) {
        case (true, 0):
            return "to me"
        case (true, 1):
            return "to me and 1 other"
        case (true, _):
            return "to me and \(others.count) others"
        case (false, 1):
            return "to \(MailFormatting.displayName(others[0].header))"
        default:
            return "to \(MailFormatting.displayName(others[0].header)) and \(others.count - 1) others"
        }
    }

    /// One initial for the sender's disc.
    ///
    /// From the name when there is one, and the address otherwise; a sender
    /// whose header begins with punctuation still gets a letter rather than a
    /// bracket.
    static func initial(for sender: String) -> String {
        let name = MailFormatting.displayName(sender)
        let source = name.isEmpty ? Draft.normalizedAddress(sender) : name
        guard let letter = source.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(letter).uppercased()
    }

    /// A stable hue for a sender's disc, 0...1.
    ///
    /// Derived from the address so one correspondent is the same colour in
    /// every thread, forever, without storing anything. Deliberately not
    /// random: a colour that changed between launches would be worse than no
    /// colour at all.
    static func hue(for sender: String) -> Double {
        let address = Draft.normalizedAddress(sender)
        let source = address.isEmpty ? sender : address
        // FNV-1a: small, stable across launches and platforms, and unlike
        // Swift's own `hashValue` it is not seeded per process.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Double(hash % 360) / 360
    }
}

import SwiftUI

/// A coloured initial standing in for a sender.
///
/// There is no avatar to fetch and no contacts API wired up, but a long thread
/// between three people is much easier to follow when each one is a different
/// colour than when they are three identical lines of text.
struct SenderDisc: View {
    let sender: String

    static let size: CGFloat = 26

    var body: some View {
        let hue = MessageAddressing.hue(for: sender)
        Circle()
            // Muted rather than saturated: this sits beside body text all the
            // way down a transcript and must not shout at it. Deep enough that
            // the white letter has something to sit on -- at 0.78 the contrast
            // was about two to one and the initial looked washed out.
            .fill(Color(hue: hue, saturation: 0.52, brightness: 0.62))
            .frame(width: Self.size, height: Self.size)
            .overlay {
                Text(MessageAddressing.initial(for: sender))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // The name is spoken beside it; a letter read aloud is noise.
            .accessibilityHidden(true)
    }
}
