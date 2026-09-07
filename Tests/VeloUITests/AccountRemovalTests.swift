import Testing
import Foundation
@testable import VeloCore

/// `AccountList.remove` was written at the start and called by nothing: an
/// account could be added and never taken away.
///
/// That matters more than it sounds. Signing in again after an expiry is easy
/// to do through "Add another account", and on the real machine it had left
/// three accounts for one address -- three databases, three partial copies, and
/// a shared announcement mark that silenced notifications in all of them.
@Suite struct AccountRemovalTests {
    private func list(test: String = #function) -> AccountList {
        AccountList(defaults: scratchDefaults(test: test))
    }

    @Test func removingOneLeavesTheRest() {
        let accounts = list()
        let second = accounts.add()
        _ = accounts.add()

        accounts.remove(second)

        #expect(!accounts.accounts.contains { $0.id == second })
        #expect(accounts.accounts.count == 2)
    }

    /// An app with no mailbox has nothing to show.
    @Test func theLastOneCannotBeRemoved() {
        let accounts = list()
        let only = accounts.accounts[0].id

        accounts.remove(only)

        #expect(accounts.accounts.count == 1)
    }

    /// Removing the open mailbox has to leave a different one open, not a
    /// dangling id pointing at a database that is no longer listed.
    @Test func removingTheOpenOneOpensAnother() {
        let accounts = list()
        let second = accounts.add()
        #expect(accounts.current == second)

        accounts.remove(second)

        #expect(accounts.current != second)
        #expect(accounts.accounts.contains { $0.id == accounts.current })
    }

    /// `current` falls back to the *literal* primary id when the stored one is
    /// gone, without checking that an account by that name still exists.
    ///
    /// `primary` is not just a name: `Account.databaseName` and
    /// `keychainAccount` special-case it to the original on-disk database and
    /// Keychain entry. So a dangling `current` does not fail loudly -- it opens
    /// the mail and credentials of an account that was deliberately removed,
    /// which is the opposite of what the confirmation promised.
    @Test func currentAlwaysNamesAnAccountThatStillExists() {
        let accounts = list()
        let a = accounts.add(), b = accounts.add()

        accounts.remove(Account.primaryID)
        accounts.remove(b)

        #expect(accounts.accounts.map(\.id) == [a])
        #expect(accounts.accounts.contains { $0.id == accounts.current },
                "current is \(accounts.current), which is not in the list")
    }

    /// The state that prompted this: three ids, one address.
    @Test func severalAccountsCanShareAnAddressAndBeTrimmedBackToOne() {
        let accounts = list()
        let a = accounts.add(), b = accounts.add()
        for id in [Account.primaryID, a, b] {
            accounts.setAddress("gede@sistercreatives.co", on: id)
        }
        #expect(Set(accounts.accounts.compactMap(\.address)).count == 1)

        accounts.remove(a)
        accounts.remove(b)

        #expect(accounts.accounts.map(\.id) == [Account.primaryID])
    }
}
