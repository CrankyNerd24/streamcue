import CloudKit

enum HouseholdShareError: LocalizedError {
    case shareRecordMissing

    var errorDescription: String? {
        switch self {
        case .shareRecordMissing:
            return "Couldn't create the household share."
        }
    }
}

/// Manual CloudKit plumbing for the household shared list.
///
/// SwiftData has no first-class support for CKShare — only automatic sync of
/// the private database — so this talks to CloudKit directly, alongside (not
/// instead of) the SwiftData/CloudKit-automatic setup that already handles
/// personal watchlists in `StreamCueApp.swift`. This is step one: create the
/// share, invite to it, accept it. No shared-list record type or data model
/// yet — that comes once this plumbing is verified working end to end.
///
/// Records in CloudKit's default zone can't be shared, so everything lives
/// in a custom zone (`zoneName`) in the current user's private database. The
/// person who accepts the invite reaches the same records through their own
/// `CKContainer.default().sharedCloudDatabase`.
enum HouseholdShareManager {
    static let zoneName = "HouseholdZone"
    private static let rootRecordType = "HouseholdRoot"
    private static let rootRecordName = "HouseholdRoot"

    private static var container: CKContainer { .default() }
    private static var privateDatabase: CKDatabase { container.privateCloudDatabase }

    private static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private static var rootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
    }

    /// Creates the household zone and root record if they don't already
    /// exist, and returns a `CKShare` for it — reusing the existing one if
    /// this device (or a previous run) already made it. Call this when the
    /// user asks to share the household list, then present the result with
    /// `CloudSharingView`.
    static func fetchOrCreateShare() async throws -> CKShare {
        try await ensureZoneExists()

        if let existingShare = try await fetchExistingShare() {
            return existingShare
        }

        do {
            return try await createShare()
        } catch {
            // The root record can already exist on the server even though
            // the fetch above just came back empty — e.g. a previous run
            // created it and this fetch raced eventual consistency. Rather
            // than fail outright on that collision, look again before
            // giving up.
            if let existingShare = try? await fetchExistingShare() {
                return existingShare
            }
            throw error
        }
    }

    /// Accepts an incoming household share. Called from `SceneDelegate` when
    /// someone taps the invite link.
    static func acceptShare(metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
    }

    // MARK: - Steps

    private static func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        // Saving a zone that already exists is a harmless no-op — CloudKit
        // doesn't error on it — so this doubles as "create if needed".
        _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    private static func fetchExistingShare() async throws -> CKShare? {
        let rootRecord: CKRecord
        do {
            rootRecord = try await privateDatabase.record(for: rootRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }

        guard let shareReference = rootRecord.share else { return nil }
        let shareRecord = try await privateDatabase.record(for: shareReference.recordID)
        return shareRecord as? CKShare
    }

    private static func createShare() async throws -> CKShare {
        let rootRecord = CKRecord(recordType: rootRecordType, recordID: rootRecordID)
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "StreamCue household list" as CKRecordValue
        share.publicPermission = .none

        let result = try await privateDatabase.modifyRecords(saving: [rootRecord, share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }

        guard case .success(let savedShareRecord) = result.saveResults[share.recordID],
              let savedShare = savedShareRecord as? CKShare
        else {
            throw HouseholdShareError.shareRecordMissing
        }
        return savedShare
    }
}
