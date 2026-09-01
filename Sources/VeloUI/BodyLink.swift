import WebKit

/// What to do when a message body asks to navigate somewhere.
///
/// Separated from the web view's delegate because it is a judgement about
/// hostile input rather than plumbing, and one worth being able to state
/// exactly: a message is written by a stranger, and every decision here either
/// hands them something or refuses them.
enum BodyLink {
    enum Decision: Equatable {
        /// The message document itself, or a subframe the content blocker
        /// already governs.
        case allow
        /// The reader asked to go somewhere. Hand it to whatever they use for
        /// that kind of address.
        case open(URL)
        /// Refuse, and do not pass it to the system either.
        case cancel
    }

    /// Schemes worth handing to the OS.
    ///
    /// A deliberately short list. `NSWorkspace.open` will launch whatever is
    /// registered for a scheme, so anything not named here -- `file:`, `data:`,
    /// `javascript:`, and every application's own custom scheme -- is refused
    /// rather than forwarded on a stranger's say-so.
    private static let handedOn: Set<String> = ["http", "https", "mailto", "tel"]

    static func decide(url: URL?, type: WKNavigationType, isMainFrame: Bool) -> Decision {
        switch type {
        case .linkActivated, .formSubmitted:
            // The reader did something. The only question is whether the
            // destination is one we are willing to pass on.
            guard let scheme = url?.scheme?.lowercased(), handedOn.contains(scheme),
                  let url else { return .cancel }
            return .open(url)

        default:
            // Nobody clicked anything. This is the document loading, a
            // subframe, or a redirect the sender wrote into the message.
            guard let url else { return .allow }
            if url.scheme?.lowercased() == "about" { return .allow }
            if !isMainFrame { return .allow }
            // A redirect is not a request from the reader. Opening a browser
            // for one would mean that merely reading a message could launch
            // whatever the sender chose.
            return .cancel
        }
    }
}
