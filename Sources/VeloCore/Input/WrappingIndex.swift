/// Moving a highlight through a list that has an end.
///
/// One place, because two lists want it -- the command palette and the
/// recipient suggestions in the composer -- and they should not disagree about
/// what Down on the last row does.
public enum WrappingIndex {
    /// `index` moved by `offset`, wrapping at both ends and always landing
    /// inside a list of `count`.
    ///
    /// Clamped as well as wrapped: a filter can shrink the list under a
    /// highlight that was further down, and the answer still has to be a row
    /// that exists.
    public static func moved(from index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let start = min(max(0, index), count - 1)
        return ((start + offset) % count + count) % count
    }
}
