import Testing
import Foundation
@testable import VeloCore

@Suite struct AccountListTests {
    private func makeStore(test: String = #function) -> AccountList {
        AccountList(defaults: scratchDefaults(test: test))
    }

    @Test func aFreshInstallHasOneAccountWaitingToBeSignedInto() {
        // Not zero: the app has always had somewhere to put mail, and calling
        // that "no accounts" would make a first launch a special case
        // everywhere.
        let list = makeStore()
        #expect(list.accounts.map(\.id) == [Account.primaryID])
        #expect(list.current == Account.primaryID)
    }

    @Test func anAccountRemembersWhoItIs() {
        let list = makeStore()
        list.setAddress("warren@example.com", on: Account.primaryID)

        #expect(list.accounts.first?.address == "warren@example.com")
    }

    @Test func addingOneGivesItAnIDOfItsOwn() {
        let list = makeStore()
        let added = list.add()

        #expect(added != Account.primaryID)
        #expect(list.accounts.count == 2)
    }

    @Test func addingSwitchesToIt() {
        // Adding an account is something you do in order to use it.
        let list = makeStore()
        let added = list.add()

        #expect(list.current == added)
    }

    @Test func theChoiceOfAccountSurvivesRelaunching() {
        let defaults = scratchDefaults()
        let first = AccountList(defaults: defaults)
        let added = first.add()

        #expect(AccountList(defaults: defaults).current == added)
    }

    @Test func switchingToSomethingUnknownIsIgnored() {
        // Better to stay where you are than to open an empty mailbox.
        let list = makeStore()
        list.switchTo("nonsense")

        #expect(list.current == Account.primaryID)
    }

    @Test func anAccountCanBeRemoved() {
        let list = makeStore()
        let added = list.add()

        list.remove(added)

        #expect(list.accounts.map(\.id) == [Account.primaryID])
        #expect(list.current == Account.primaryID)
    }

    @Test func theLastAccountCannotBeRemoved() {
        // There is always a mailbox; an app with none has nothing to show.
        let list = makeStore()
        list.remove(Account.primaryID)

        #expect(list.accounts.count == 1)
    }

    // MARK: - Keeping accounts apart

    @Test func eachAccountGetsItsOwnDatabase() {
        #expect(Account.databaseName(for: Account.primaryID) == "velomail.sqlite")
        #expect(Account.databaseName(for: "abc") == "velomail-abc.sqlite")
    }

    @Test func thePrimaryKeepsTheFileItAlreadyHas() {
        // A mailbox already on disk must not be orphaned by adding a second
        // account.
        #expect(Account.databaseName(for: Account.primaryID) == "velomail.sqlite")
    }

    @Test func eachAccountGetsItsOwnKeychainEntry() {
        #expect(Account.keychainAccount(for: Account.primaryID) == "default")
        #expect(Account.keychainAccount(for: "abc") == "abc")
    }
}
