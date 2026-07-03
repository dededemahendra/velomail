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
