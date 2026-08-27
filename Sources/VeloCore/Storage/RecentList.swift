import Foundation

/// A short, ordered, de-duplicated list of the last things used.
///
/// The same rule serves recent commands and recent searches: newest first, no
/// repeats, and capped, because beyond a handful the top of a list stops being
/// a shortcut and becomes a second catalogue.
public enum RecentList {
    public static func remember<Item: Equatable>(_ used: Item, in previous: [Item],
                                                 limit: Int) -> [Item] {
        ([used] + previous.filter { $0 != used }).prefix(limit).map { $0 }
    }
}
