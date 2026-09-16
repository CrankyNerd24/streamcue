import CloudKit

enum SharedListError: LocalizedError {
    case notSetUp

    var errorDescription: String? {
        switch self {
        case .notSetUp:
            return "There's no household list yet — create or accept a share first."
        }
    }
}

/// CRUD for the household's shared list, stored as raw `SharedItem` CloudKit
/// records in the same custom zone the household share lives in
/// (`HouseholdShareManager.zoneName`) — SwiftData can't participate in a
/// CloudKit share, so this bypasses it entirely, same as
/// `HouseholdShareManager` does for the share itself.
enum SharedListManager {
    /// Where this device reads and writes shared-list records. The person
    /// who created the household reads/writes their own private database;
    /// everyone who accepted an invite reaches the same zone through the
    /// shared database instead, under the owner's zone ID rather than their
    /// own — CloudKit surfaces that zone via `sharedCloudDatabase.allRecordZones()`
    /// once the invite's been accepted.
    private struct Context {
        let database: CKDatabase
        let zoneID: CKRecordZone.ID
    }

    private static var container: CKContainer { .default() }

    /// Checks the shared database — "am I a participant in someone else's
    /// household?" — before ever looking at a zone this device owns itself.
    /// Zone names aren't unique across accounts: if this device ever tapped
    /// "Invite to household list" itself, even by mistake, it owns its own
    /// zone of the same name, and checking owned-first would resolve to
    /// that instead, permanently shadowing the household it actually
    /// joined. Joining always wins over owning.
    private static func resolveContext() async throws -> Context {
        if let zone = try await sharedHouseholdZone() {
            return Context(database: container.sharedCloudDatabase, zoneID: zone.zoneID)
        }

        let ownedZoneID = CKRecordZone.ID(
            zoneName: HouseholdShareManager.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        guard (try? await container.privateCloudDatabase.recordZone(for: ownedZoneID)) != nil else {
            throw SharedListError.notSetUp
        }
        return Context(database: container.privateCloudDatabase, zoneID: ownedZoneID)
    }

    private static func sharedHouseholdZone() async throws -> CKRecordZone? {
        let zones = try await container.sharedCloudDatabase.allRecordZones()
        return zones.first { $0.zoneID.zoneName == HouseholdShareManager.zoneName }
    }

    /// True if this device is a participant in a household someone else
    /// owns — used to hide "Invite to household list" for joiners, so they
    /// can't accidentally create a second, competing household of their own.
    static func isParticipantInSharedHousehold() async -> Bool {
        (try? await sharedHouseholdZone()) != nil
    }

    private static func rootRecordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: HouseholdShareManager.rootRecordName, zoneID: zoneID)
    }

    static func fetchAll() async throws -> [SharedItem] {
        let context = try await resolveContext()
        // Not NSPredicate(value: true): a true predicate needs the system
        // recordName field marked queryable, which isn't set up by default.
        // Filtering on addedAt (a normal field, auto-indexed on first save)
        // matches everything without that requirement.
        let query = CKQuery(
            recordType: SharedItem.recordType,
            predicate: NSPredicate(format: "%K < %@", SharedItem.Field.addedAt, Date.distantFuture as NSDate)
        )
        query.sortDescriptors = [NSSortDescriptor(key: SharedItem.Field.addedAt, ascending: false)]

        do {
            let (matches, _) = try await context.database.records(matching: query, inZoneWith: context.zoneID)
            return matches.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return SharedItem(record: record)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No SharedItem has ever been saved, so CloudKit's schema (which
            // it infers from the first save, in Development) doesn't know
            // the record type yet — that's "nothing on the list", not a
            // real failure.
            return []
        }
    }

    /// Saves an independent copy of a title onto the shared list — no
    /// ongoing link back to whatever personal-list item it came from.
    @discardableResult
    static func add(tmdbID: Int, kind: MediaKind, title: String, posterPath: String?) async throws -> SharedItem {
        let context = try await resolveContext()
        let record = CKRecord(recordType: SharedItem.recordType, zoneID: context.zoneID)
        record.parent = CKRecord.Reference(recordID: rootRecordID(in: context.zoneID), action: .none)

        SharedItem(
            recordID: record.recordID,
            tmdbID: tmdbID,
            kind: kind,
            title: title,
            posterPath: posterPath,
            watched: false,
            addedAt: .now
        ).apply(to: record)

        let saved = try await context.database.save(record)
        guard let item = SharedItem(record: saved) else { throw SharedListError.notSetUp }
        return item
    }

    /// The shared watched flag — anyone in the household can flip it, and
    /// there's no per-person tracking of who has or hasn't seen it.
    static func setWatched(_ item: SharedItem, watched: Bool) async throws {
        let context = try await resolveContext()
        let record = try await context.database.record(for: item.recordID)
        record[SharedItem.Field.watched] = (watched ? 1 : 0) as CKRecordValue
        _ = try await context.database.save(record)
    }

    static func remove(_ item: SharedItem) async throws {
        let context = try await resolveContext()
        _ = try await context.database.deleteRecord(withID: item.recordID)
    }
}
