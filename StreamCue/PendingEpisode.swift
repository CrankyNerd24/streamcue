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
        var insertedNew = false
        // Episodes the household already marked watched come in watched, so
        // they never land in Ready to watch here.
        let sharedWatched = SharedListStore.shared.item(tmdbID: show.tmdbID, kind: .tv)?.watchedEpisodes ?? []

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

            let record = PendingEpisode(
                showID: show.tmdbID,
                showName: show.name,
                posterPath: show.posterPath,
                seasonNumber: seasonNumber,
                episodeNumber: number,
                title: episode.name,
                airDate: airDate
            )
            if sharedWatched.contains(SharedItem.episodeKey(season: seasonNumber, episode: number)) {
                record.watched = true
            } else {
                insertedNew = true
            }
            context.insert(record)
        }

        // A newly aired episode un-catches-you-up — "watched" for a show
        // means caught up as of now, not caught up forever. One someone else
        // in the household already watched doesn't count.
        if insertedNew && show.watched {
            show.watched = false
            await SharedListStore.shared.syncWatched(tmdbID: show.tmdbID, kind: .tv, watched: false)
        }
    }

    /// Marks this device's copies of the household's watched episodes as
    /// watched, then catches the show up if that leaves nothing outstanding.
    /// Watched wins, like the show-level flag: this never un-watches
    /// anything, and leaves an episode you dismissed as it is.
    static func applySharedWatched(_ keys: Set<String>, to show: TrackedShow, context: ModelContext) {
        guard !keys.isEmpty else { return }
        let id = show.tmdbID
        let descriptor = FetchDescriptor<PendingEpisode>(predicate: #Predicate { $0.showID == id })
        let episodes = (try? context.fetch(descriptor)) ?? []

        var changed = false
        for episode in episodes where !episode.watched && !episode.dismissed {
            guard keys.contains(SharedItem.episodeKey(season: episode.seasonNumber, episode: episode.episodeNumber)) else { continue }
            episode.watched = true
            changed = true
        }

        let outstanding = episodes.contains { !$0.watched && !$0.dismissed }
        if changed && !outstanding && !show.watched {
            show.watched = true
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
