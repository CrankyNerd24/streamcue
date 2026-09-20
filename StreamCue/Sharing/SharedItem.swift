import Foundation
import CloudKit

/// One entry on the household's shared list — a snapshot of a show or
/// film's identity plus a shared watched flag anyone in the household can
/// toggle. Deliberately not linked back to whichever personal
/// `TrackedShow`/`TrackedMovie` it was added from: removing it from the
/// shared list, or from someone's personal list, never affects the other.
///
/// Backed by a raw CloudKit record rather than SwiftData — SwiftData has no
/// support for records living in a shared CKShare zone, only automatic
/// private-database sync (see `HouseholdShareManager`).
struct SharedItem: Identifiable, Equatable {
    static let recordType = "SharedItem"

    enum Field {
        static let tmdbID = "tmdbID"
        static let kind = "kind"
        static let title = "title"
        static let posterPath = "posterPath"
        static let watched = "watched"
        static let addedAt = "addedAt"
    }

    var recordID: CKRecord.ID
    var tmdbID: Int
    var kind: MediaKind
    var title: String
    var posterPath: String?
    var watched: Bool
    var addedAt: Date

    var id: CKRecord.ID { recordID }
}

extension SharedItem {
    init?(record: CKRecord) {
        guard
            let tmdbID = record[Field.tmdbID] as? Int,
            let kindRaw = record[Field.kind] as? String,
            let kind = MediaKind(rawValue: kindRaw),
            let title = record[Field.title] as? String,
            let addedAt = record[Field.addedAt] as? Date
        else { return nil }

        self.recordID = record.recordID
        self.tmdbID = tmdbID
        self.kind = kind
        self.title = title
        self.posterPath = record[Field.posterPath] as? String
        self.watched = ((record[Field.watched] as? Int) ?? 0) != 0
        self.addedAt = addedAt
    }

    func apply(to record: CKRecord) {
        record[Field.tmdbID] = tmdbID as CKRecordValue
        record[Field.kind] = kind.rawValue as CKRecordValue
        record[Field.title] = title as CKRecordValue
        record[Field.posterPath] = posterPath as CKRecordValue?
        record[Field.watched] = (watched ? 1 : 0) as CKRecordValue
        record[Field.addedAt] = addedAt as CKRecordValue
    }
}
