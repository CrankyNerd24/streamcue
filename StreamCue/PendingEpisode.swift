import Foundation
import SwiftData

/// An episode that has already aired and hasn't been watched or dismissed.
@Model
final class PendingEpisode {
    /// "showID-season-episode". Not a unique constraint — CloudKit doesn't
    /// support those — so the sync checks for an existing record instead.
    var key: String = ""

    var showID: Int = 0
    var showName: String = ""
    var posterPath: String?
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    var title: String?
    var airDate: Date?
    var watched: Bool = false
    var dismissed: Bool = false
    var addedAt: Date = Date.now

    init(
        showID: Int,
        showName: String,
        posterPath: String?,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String?,
        airDate: Date?
    ) {
        self.key = "\(showID)-\(seasonNumber)-\(episodeNumber)"
        self.showID = showID
        self.showName = showName
        self.posterPath = posterPath
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.airDate = airDate
        self.watched = false
        self.dismissed = false
        self.addedAt = .now
    }
}

extension PendingEpisode {
    var label: String {
        let number = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
        guard let title, !title.isEmpty else { return number }
        return "\(number) · \(title)"
    }

    var airedSummary: String {
        guard let airDate else { return "Aired" }
        if Calendar.current.isDateInToday(airDate) { return "Aired today" }
        return "Aired \(airDate.formatted(.dateTime.weekday(.abbreviated).month().day()))"
    }
}

/// Pulls a show's current season and records anything that has aired recently.
/// TMDB only reports the single most recent episode on the details endpoint, so
/// catching up after a gap needs the season list.
@MainActor
enum EpisodeSync {
    /// How far back to look. Stops a newly added show from dumping a whole
    /// back catalogue into the list.
    static let window: TimeInterval = 30 * 24 * 60 * 60

    /// Records older than this are deleted outright, actioned or not. Safe
    /// because it's longer than `window` — nothing this old can be re-added.
    static let expiry: TimeInterval = 60 * 24 * 60 * 60

    static func sync(_ show: TrackedShow, context: ModelContext) async {
        guard let seasonNumber = show.lastAiredSeason else { return }
        guard let season = try? await TMDBClient.shared.season(
            showID: show.tmdbID,
            number: seasonNumber
        ) else { return }

        let cutoff = Date().addingTimeInterval(-window)

        for episode in season.episodes {
            guard let number = episode.episodeNumber,
                  let broadcast = TMDBDate.parse(episode.airDate) else { continue }

            // Bake the show's offset in at sync time. Changing the offset later
            // won't retouch episodes already recorded — they age out within 60
            // days, which isn't worth a lookup from every episode to its show.
            let airDate = show.dayOffset == 0
                ? broadcast
                : Calendar.current.date(byAdding: .day, value: show.dayOffset, to: broadcast) ?? broadcast

            guard airDate <= .now, airDate >= cutoff else { continue }

            let key = "\(show.tmdbID)-\(seasonNumber)-\(number)"
            var descriptor = FetchDescriptor<PendingEpisode>(
                predicate: #Predicate { $0.key == key }
            )
            descriptor.fetchLimit = 1
            let existing = (try? context.fetch(descriptor)) ?? []
            guard existing.isEmpty else { continue }

            context.insert(PendingEpisode(
                showID: show.tmdbID,
                showName: show.name,
                posterPath: show.posterPath,
                seasonNumber: seasonNumber,
                episodeNumber: number,
                title: episode.name,
                airDate: airDate
            ))
        }
    }

    /// Drops anything that aired more than `expiry` ago. Covers unactioned
    /// episodes you never got to as well as watched and dismissed records,
    /// which would otherwise accumulate forever.
    static func prune(context: ModelContext) {
        let cutoff = Date().addingTimeInterval(-expiry)
        let all = (try? context.fetch(FetchDescriptor<PendingEpisode>())) ?? []
        for episode in all {
            guard let airDate = episode.airDate else { continue }
            if airDate < cutoff { context.delete(episode) }
        }
    }

    /// Called when a show is removed, so its episodes don't linger.
    static func removeAll(forShowID id: Int, context: ModelContext) {
        let descriptor = FetchDescriptor<PendingEpisode>(
            predicate: #Predicate { $0.showID == id }
        )
        for episode in (try? context.fetch(descriptor)) ?? [] {
            context.delete(episode)
        }
    }
}
