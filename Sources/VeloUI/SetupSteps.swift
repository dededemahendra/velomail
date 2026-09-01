import Foundation

/// What a first launch has to explain, as steps rather than as a paragraph.
///
/// It was one block of prose with bullets inside it, which is the shape text
/// takes when nobody has decided what the reader is meant to *do*. Someone
/// arriving here has no mail and no idea why; they need an ordered list, the
/// exact strings to paste, and a way to look around without doing any of it.
public struct SetupStep: Equatable, Sendable, Identifiable {
    public let number: Int
    public let title: String
    public let detail: String
    /// Something to copy verbatim, when the step has one.
    public let snippet: String?
    /// Where the step is done, when it is done somewhere else.
    public let link: URL?

    public var id: Int { number }
}

public enum Setup {
    public static let steps: [SetupStep] = [
        SetupStep(
            number: 1,
            title: "Create a Google OAuth client",
            detail: "A Desktop app client, with the Gmail API enabled. "
                + "Google Cloud Console, under APIs & Services → Credentials.",
            snippet: nil,
            link: URL(string: "https://console.cloud.google.com/apis/credentials")),
        SetupStep(
            number: 2,
            title: "Give Velo Mail the client id",
            detail: "Either as an environment variable, or in a config file. "
                + "A Desktop client also has a secret; add it the same way. "
                + "An iOS client has none.",
            snippet: """
                export VELOMAIL_CLIENT_ID="…apps.googleusercontent.com"
                export VELOMAIL_CLIENT_SECRET="GOCSPX-…"
                """,
            link: nil),
        SetupStep(
            number: 3,
            title: "Or write it to the config file",
            detail: "The same two values, if you would rather not set them in a shell.",
            snippet: """
                ~/.config/velomail/config.json
                { "clientID": "…", "clientSecret": "…" }
                """,
            link: nil),
        SetupStep(
            number: 4,
            title: "Restart Velo Mail",
            detail: "The credentials are read once, at launch.",
            snippet: nil,
            link: nil),
    ]

    /// The way out for somebody who wants to see the app before setting any of
    /// this up. Offered rather than buried: a first screen that only makes
    /// demands is a first screen people close.
    public static let demoHint = "VELOMAIL_DEMO=1 VeloMail.app/Contents/MacOS/VeloMail"
}
