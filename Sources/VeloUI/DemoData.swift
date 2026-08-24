import Foundation
import VeloCore

/// Sample mail so the app can be launched and reviewed without credentials and
/// without touching the network.
enum DemoData {
    static func seed(into store: MailStore) throws {
        let now = Date()
        let samples: [(id: String, from: String, subject: String, snippet: String, body: String, unread: Bool)] = [
            ("t1", "Natalie Roberts <natalie@sistercreatives.co>", "Mornington Green open day",
             "Numbers for Saturday are in, and we are close to capacity.",
             "<p>Numbers for Saturday are in, and we are close to capacity.</p><p>Do we open a second session?</p>", true),
            ("t2", "Gede Mahendra <gede@sistercreatives.co>", "Sanity schema migration",
             "Pushed the memorial-tree schema change to preview.",
             "<p>Pushed the memorial-tree schema change to preview. Have a look before I promote it.</p>", true),
            ("t3", "Peta Bilston <peta@wellingtondam.org.au>", "Wellington Dam plantings",
             "Confirming the two-ashes-per-tree cap in the new brochure.",
             "<p>Confirming the two-ashes-per-tree cap is stated clearly in the new brochure.</p>", false),
            ("t4", "Luke Roberts <luke@livinglegacyforest.com>", "Patent renewal",
             "The AU renewal is due next quarter.",
             "<p>The AU renewal is due next quarter. Forwarding the attorney's note.</p>", false),
            ("t5", "Stripe <receipts@stripe.com>", "Your receipt",
             "Receipt for the monthly subscription.",
             "<p>Receipt for the monthly subscription.</p>", false),
        ]

        // A multi-message thread, so the transcript (newest expanded, older
        // collapsed) is exercised rather than just the single-message path.
        let conversation: [(id: String, from: String, body: String, minutesAgo: Int)] = [
            ("c1", "Warren Roberts <warren@livinglegacyforest.com>",
             "Can we get the Somerville plot map updated before the open day?", 180),
            ("c2", "Salsa <salsa@sistercreatives.co>",
             "Yes. I have the survey file, will redraw the eastern boundary today.", 120),
            ("c3", "Warren Roberts <warren@livinglegacyforest.com>",
             "Perfect. Send it to Natalie when it is done and she will print it.", 0),
        ]
        try store.upsert(MailThread(id: "conv", sender: conversation.last!.from,
                                    snippet: conversation.last!.body,
                                    lastMessageDate: now,
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        for message in conversation {
            let date = now.addingTimeInterval(TimeInterval(-message.minutesAgo * 60))
            try store.upsert(Message(id: message.id, threadID: "conv", sender: message.from,
                                     recipients: ["warren@livinglegacyforest.com"],
                                     subject: "Somerville plot map", date: date,
                                     bodyHTML: "<p>\(message.body)</p>", bodyText: message.body,
                                     isUnread: false, labelIDs: ["INBOX"],
                                     messageIDHeader: "<\(message.id)@demo.velomail>"))
        }

        for (offset, sample) in samples.enumerated() {
            let date = now.addingTimeInterval(TimeInterval(-(offset + 1) * 3600))
            let labels = sample.unread ? ["INBOX", "UNREAD"] : ["INBOX"]
            try store.upsert(MailThread(id: sample.id, sender: sample.from, snippet: sample.snippet, lastMessageDate: date,
                                        isUnread: sample.unread, hasAttachments: false, labelIDs: labels))
            try store.upsert(Message(id: "m-\(sample.id)", threadID: sample.id, sender: sample.from,
                                     recipients: ["warren@livinglegacyforest.com"],
                                     subject: sample.subject, date: date,
                                     bodyHTML: sample.body, bodyText: sample.snippet,
                                     isUnread: sample.unread, labelIDs: labels,
                                     messageIDHeader: "<\(sample.id)@demo.velomail>"))
        }
    }
}
