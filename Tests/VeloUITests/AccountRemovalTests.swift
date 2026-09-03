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
    private func list() -> AccountList {
        AccountList(defaults: UserDefaults(suiteName: "velo.accounts.\(UUID())")!)
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
