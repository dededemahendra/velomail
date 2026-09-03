import Foundation

/// A `UserDefaults` for one test, cleared before that test starts.
///
/// These used to be named after a fresh UUID, and `UserDefaults(suiteName:)` is
/// disk-backed: it writes to ~/Library/Preferences the moment anything is
/// stored in it. A new name every run therefore meant a new file every run.
/// 9,371 of them had accumulated in the users Library, 17 MB, growing by a
/// few hundred with every `swift test`.
///
/// Cleaning up afterwards does not work, which was measured rather than
/// assumed: `removePersistentDomain` empties a domain without removing its
/// file, and deleting the file does not keep it deleted, because cfprefsd
/// rewrites it from cache when the process exits.
///
/// So the name is derived from the test instead. Still unique per test, so no
/// test can see another one state, but the same name on every run, which
/// bounds the files by the number of tests rather than by how often they are
/// run. Helpers that call this must thread `test:` through from their own
/// `#function` default, or every test in the file shares one suite.
func scratchDefaults(file: String = #fileID, test: String = #function) -> UserDefaults {
    let leaf = file.split(separator: "/").last.map { $0.replacingOccurrences(of: ".swift", with: "") }
    let name = "velo.scratch.\(leaf ?? "tests").\(test.prefix { $0 != "(" })"
    let defaults = UserDefaults(suiteName: name)!
    // A leftover from a previous run must not decide this one.
    defaults.removePersistentDomain(forName: name)
    return defaults
}
