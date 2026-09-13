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

    private static func resolveContext() async throws -> Context {
        let ownedZoneID = CKRecordZone.ID(
            zoneName: HouseholdShareManager.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let privateDatabase = container.privateCloudDatabase
        if (try? await privateDatabase.recordZone(for: ownedZoneID)) != nil {
            return Context(database: privateDatabase, zoneID: ownedZoneID)
        }

        let sharedDatabase = container.sharedCloudDatabase
        let zones = try await sharedDatabase.allRecordZones()
        guard let zone = zones.first(where: { $0.zoneID.zoneName == HouseholdShareManager.zoneName }) else {
            throw SharedListError.notSetUp
        }
        return Context(database: sharedDatabase, zoneID: zone.zoneID)
    }

    private static func rootRecordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: HouseholdShareManager.rootRecordName, zoneID: zoneID)
    }

    static func fetchAll() async throws -> [SharedItem] {
        let context = try await resolveContext()
        let query = CKQuery(recordType: SharedItem.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: SharedItem.Field.addedAt, ascending: false)]

        let (matches, _) = try await context.database.records(matching: query, inZoneWith: context.zoneID)
        return matches.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return SharedItem(record: record)
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
