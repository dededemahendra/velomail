import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct PendingMutationTests {
    private func sample(kind: MutationKind = .archive) -> PendingMutation {
        PendingMutation(kind: kind, payload: Data("{}".utf8),
                        createdAt: Date(timeIntervalSince1970: 1000), status: .pending)
    }

    @Test func insertAssignsAutoincrementID() throws {
        let db = try AppDatabase.makeInMemory()
        var m = sample()
        try db.dbQueue.write { try m.insert($0) }
        #expect(m.id == 1)
    }

    @Test func roundTripsThroughDatabase() throws {
        let db = try AppDatabase.makeInMemory()
        var m = PendingMutation(kind: .markRead, payload: Data("payload".utf8),
                                createdAt: Date(timeIntervalSince1970: 2500), status: .pending)
        try db.dbQueue.write { try m.insert($0) }

        let fetched = try db.dbQueue.read { try PendingMutation.fetchOne($0, key: m.id!) }
        #expect(fetched?.kind == .markRead)
        #expect(fetched?.status == .pending)
        #expect(fetched?.payload == Data("payload".utf8))
        #expect(fetched?.createdAt.timeIntervalSince1970 == 2500)
    }

    @Test func storesEnumsAsRawText() throws {
        let db = try AppDatabase.makeInMemory()
        var m = sample()
        try db.dbQueue.write { try m.insert($0) }

        let row = try db.dbQueue.read { try Row.fetchOne($0, sql: "SELECT kind, status FROM pendingMutation") }
        #expect(row?["kind"] == "archive")
        #expect(row?["status"] == "pending")
    }

    @Test func starAndUnstarRoundTripThroughTheMutationKindCoding() throws {
        let db = try AppDatabase.makeInMemory()
        var star = sample(kind: .star)
        var unstar = sample(kind: .unstar)
        try db.dbQueue.write { db in
            try star.insert(db)
            try unstar.insert(db)
        }

        let kinds = try db.dbQueue.read {
            try PendingMutation.fetchAll($0).map(\.kind)
        }
        #expect(kinds == [.star, .unstar])

        // Stored as raw text like every other kind, so a queue written by this
        // version is still readable by anything that reads the column.
        let raw = try db.dbQueue.read {
            try String.fetchAll($0, sql: "SELECT kind FROM pendingMutation ORDER BY id")
        }
        #expect(raw == ["star", "unstar"])
    }

    @Test func sequentialInsertsGetAscendingIDs() throws {
        let db = try AppDatabase.makeInMemory()
        var first = sample()
        var second = sample()
        try db.dbQueue.write { db in
            try first.insert(db)
            try second.insert(db)
        }
        #expect(second.id! > first.id!)
    }
}
