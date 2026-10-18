import Foundation
import SwiftData

/// One ticked-off episode in the full per-episode progress checklist for an
/// ended/canceled show. Deliberately sparse — only watched episodes are
/// stored here, not a full show's episode list, which is instead fetched
/// live from TMDB (`TMDBClient.shared.season`) and cross-referenced against
/// these records when a season is viewed.
@Model
final class WatchedEpisode {
    // No @Attribute(.unique): CloudKit can't enforce uniqueness across
    // devices that are temporarily offline. Every stored property needs a
    // default for CloudKit.
    var key: String = ""
    var showID: Int = 0
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    var watchedAt: Date = Date.now

    init(showID: Int, seasonNumber: Int, episodeNumber: Int) {
        self.key = Self.makeKey(showID: showID, season: seasonNumber, episode: episodeNumber)
        self.showID = showID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.watchedAt = .now
    }

    static func makeKey(showID: Int, season: Int, episode: Int) -> String {
        "\(showID)-\(season)-\(episode)"
    }
}
