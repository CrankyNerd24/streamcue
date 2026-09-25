import Foundation
import SwiftData

@Model
final class TrackedShow {
    // No @Attribute(.unique): CloudKit can't enforce uniqueness across devices
    // that are temporarily offline. Deduplication happens at insert time in
    // Library instead. Every stored property needs a default for CloudKit.
    var tmdbID: Int = 0
    var name: String = ""
    var posterPath: String?
    var status: String = ""
    /// Manual, independent of per-episode tracking — same as TrackedMovie's
    /// watched. It's what the household list's shared watched flag mirrors.
    var watched: Bool = false
    var nextEpisodeLabel: String?
    var nextAirDate: Date?
    var lastEpisodeLabel: String?
    var subscriptionOn: [String] = []
    var freeOn: [String] = []
    var rentOrBuyOn: [String] = []
    /// JustWatch page for this title in the current region — where "where to
    /// watch" actually sends you when you tap it.
    var watchLink: String?
    /// Per-show "Watch on" override — see `StreamingServices.Override`.
    /// Nil name means automatic.
    var watchOnName: String?
    var watchOnLink: String?
    var addedAt: Date = Date.now
    var lastRefreshed: Date?
    var reminderID: String?

    /// The air date the reminder was created for. Lets a shifted date replace
    /// a stale reminder instead of leaving one pointing at the wrong day.
    var reminderDate: Date?
    var genreIDs: [Int] = []
    var overview: String = ""
    var nextEpisodeOverview: String?
    var lastAiredSeason: Int?

    /// Days to shift TMDB's air date by, for shows that reach you later than
    /// the original broadcast. Applied through `effectiveAirDate` — never read
    /// `nextAirDate` directly for anything user-facing.
    var dayOffset: Int = 0

    // Ratings
    var imdbID: String?
    var tmdbScore: Double?
    var tmdbVotes: Int?
    var imdbScore: String?
    var rottenTomatoesScore: String?
    var metacriticScore: String?

    init(tmdbID: Int, name: String, posterPath: String? = nil) {
        self.tmdbID = tmdbID
        self.name = name
        self.posterPath = posterPath
        self.status = ""
        self.watched = false
        self.subscriptionOn = []
        self.freeOn = []
        self.rentOrBuyOn = []
        self.addedAt = .now
    }
}

extension TrackedShow {
    var watchOnOverride: StreamingServices.Override? {
        guard let watchOnName, !watchOnName.isEmpty else { return nil }
        return StreamingServices.Override(name: watchOnName, link: watchOnLink)
    }

    /// Where Watch now goes for this show, honouring the override.
    func watchNowDestination(mySubscriptions: Set<String>) -> StreamingServices.Destination? {
        StreamingServices.destination(
            free: freeOn,
            subscription: subscriptionOn,
            rentOrBuy: rentOrBuyOn,
            mySubscriptions: mySubscriptions,
            watchLink: watchLink,
            override: watchOnOverride
        )
    }

    /// The air date as it applies to you. Every grouping, label, notification
    /// and reminder reads this rather than `nextAirDate`, so a shifted show
    /// can't say Thursday in one place and Wednesday in another.
    var effectiveAirDate: Date? {
        guard let nextAirDate else { return nil }
        guard dayOffset != 0 else { return nextAirDate }
        return Calendar.current.date(byAdding: .day, value: dayOffset, to: nextAirDate)
    }

    /// Human-readable line for the list row.
    var scheduleSummary: String {
        if let effectiveAirDate {
            let when = effectiveAirDate.formatted(.dateTime.weekday(.abbreviated).month().day())
            return [nextEpisodeLabel, when].compactMap { $0 }.joined(separator: " · ")
        }
        switch status {
        case "Ended": return "Ended"
        case "Canceled", "Cancelled": return "Canceled"
        case "Returning Series": return "Returning — no date announced"
        default: return status.isEmpty ? "Not loaded yet" : status
        }
    }

    var isFreeSomewhere: Bool { !freeOn.isEmpty }

    /// Best single score to show in a compact space.
    var headlineRating: String? {
        if let imdbScore { return "IMDb \(imdbScore)" }
        if let tmdbScore, tmdbScore > 0 {
            return "TMDB \(String(format: "%.1f", tmdbScore))"
        }
        return nil
    }

    var hasAnyRating: Bool {
        imdbScore != nil || rottenTomatoesScore != nil
            || metacriticScore != nil || (tmdbScore ?? 0) > 0
    }

    /// How long data stays good enough to skip on a background refresh.
    static let staleAfter: TimeInterval = 6 * 60 * 60

    var isStale: Bool {
        guard let lastRefreshed else { return true }
        return Date().timeIntervalSince(lastRefreshed) > Self.staleAfter
    }

    /// - Parameter includeRatings: pass false on automatic refreshes. Ratings
    ///   are still fetched for shows that have none, but OMDb's daily quota is
    ///   small and scores barely move, so it isn't worth spending on every open.
    @MainActor
    func refresh(includeRatings: Bool = true) async throws {
        let details = try await TMDBClient.shared.details(id: tmdbID)
        let availability = try await TMDBClient.shared.availability(id: tmdbID)

        name = details.name
        posterPath = details.posterPath
        status = details.status
        tmdbScore = details.voteAverage
        tmdbVotes = details.voteCount
        genreIDs = (details.genres ?? []).map(\.id)
        imdbID = details.externalIds?.imdbId
        overview = details.overview
        nextEpisodeOverview = details.nextEpisodeToAir?.overview
        nextEpisodeLabel = details.nextEpisodeToAir?.label
        nextAirDate = TMDBDate.parse(details.nextEpisodeToAir?.airDate)
        lastEpisodeLabel = details.lastEpisodeToAir?.label
        lastAiredSeason = details.lastEpisodeToAir?.seasonNumber
        subscriptionOn = availability.subscription
        freeOn = availability.free
        rentOrBuyOn = availability.rentOrBuy
        watchLink = availability.link
        lastRefreshed = .now

        // Ratings are a bonus — never let a failure here break the refresh.
        if includeRatings || imdbScore == nil, let imdbID, !imdbID.isEmpty {
            if let scores = try? await OMDbClient.shared.scores(imdbID: imdbID) {
                imdbScore = scores.imdb
                rottenTomatoesScore = scores.rottenTomatoes
                metacriticScore = scores.metacritic
            }
        }
    }
}
