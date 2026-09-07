import Foundation
import SwiftData

/// Something you've said you're not interested in. Kept as a record rather
/// than a flag so it survives, syncs, and can be undone from Settings.
/// CloudKit-legal: no unique constraint, defaults on everything.
@Model
final class IgnoredTitle {
    var tmdbID: Int = 0
    var kindRaw: String = "TV"
    var title: String = ""
    var posterPath: String?
    var addedAt: Date = Date.now

    init(tmdbID: Int, kind: MediaKind, title: String, posterPath: String? = nil) {
        self.tmdbID = tmdbID
        self.kindRaw = kind.rawValue
        self.title = title
        self.posterPath = posterPath
        self.addedAt = .now
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .tv
    }
}

extension Collection where Element == IgnoredTitle {
    /// IDs for one kind, ready to test against a feed's results.
    func ids(for kind: MediaKind) -> Set<Int> {
        Set(lazy.filter { $0.kindRaw == kind.rawValue }.map(\.tmdbID))
    }
}
