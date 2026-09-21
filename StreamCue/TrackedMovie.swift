import Foundation
import SwiftData

@Model
final class TrackedMovie {
    // See TrackedShow: no unique constraint, defaults on everything.
    var tmdbID: Int = 0
    var title: String = ""
    var posterPath: String?
    var releaseDate: Date?
    var status: String = ""
    var runtime: Int?
    var watched: Bool = false

    var freeOn: [String] = []
    var subscriptionOn: [String] = []
    var rentOrBuyOn: [String] = []
    /// JustWatch page for this title in the current region — where "where to
    /// watch" actually sends you when you tap it.
    var watchLink: String?

    var imdbID: String?
    var tmdbScore: Double?
    var imdbScore: String?
    var rottenTomatoesScore: String?
    var metacriticScore: String?

    var addedAt: Date = Date.now
    var lastRefreshed: Date?
    var genreIDs: [Int] = []
    var overview: String = ""

    init(tmdbID: Int, title: String, posterPath: String? = nil) {
        self.tmdbID = tmdbID
        self.title = title
        self.posterPath = posterPath
        self.status = ""
        self.watched = false
        self.freeOn = []
        self.subscriptionOn = []
        self.rentOrBuyOn = []
        self.addedAt = .now
    }
}

/// How you can watch it right now — the watchlist's organising idea.
enum MovieAvailability: Int, CaseIterable {
    case free
    case subscription
    case rentOrBuy
    case unavailable

    var title: String {
        switch self {
        case .free: return "Free to watch"
        case .subscription: return "On a subscription"
        case .rentOrBuy: return "Rent or buy"
        case .unavailable: return "Not streaming yet"
        }
    }
}

extension TrackedMovie {
    var availability: MovieAvailability {
        if !freeOn.isEmpty { return .free }
        if !subscriptionOn.isEmpty { return .subscription }
        if !rentOrBuyOn.isEmpty { return .rentOrBuy }
        return .unavailable
    }

    var year: String? {
        guard let releaseDate else { return nil }
        return releaseDate.formatted(.dateTime.year())
    }

    /// "2024 · 1h 47m"
    var subtitle: String {
        var parts: [String] = []
        if let year { parts.append(year) }
        if let runtime, runtime > 0 {
            parts.append(runtime >= 60
                ? "\(runtime / 60)h \(runtime % 60)m"
                : "\(runtime)m")
        }
        switch availability {
        case .free where !freeOn.isEmpty:
            parts.append(freeOn.joined(separator: ", "))
        case .subscription where !subscriptionOn.isEmpty:
            parts.append(subscriptionOn.joined(separator: ", "))
        default:
            break
        }
        return parts.joined(separator: " · ")
    }

    var primaryScore: (String, String)? {
        if let imdbScore { return (imdbScore, "IMDb") }
        if let tmdbScore, tmdbScore > 0 {
            return (String(format: "%.1f", tmdbScore), "TMDB")
        }
        return nil
    }

    var hasAnyRating: Bool {
        imdbScore != nil || rottenTomatoesScore != nil
            || metacriticScore != nil || (tmdbScore ?? 0) > 0
    }

    var isStale: Bool {
        guard let lastRefreshed else { return true }
        return Date().timeIntervalSince(lastRefreshed) > TrackedShow.staleAfter
    }

    @MainActor
    func refresh(includeRatings: Bool = true) async throws {
        let details = try await TMDBClient.shared.movieDetails(id: tmdbID)
        let availability = try await TMDBClient.shared.movieAvailability(id: tmdbID)

        title = details.title
        overview = details.overview
        posterPath = details.posterPath
        status = details.status
        runtime = details.runtime
        releaseDate = TMDBDate.parse(details.releaseDate)
        tmdbScore = details.voteAverage
        genreIDs = (details.genres ?? []).map(\.id)
        imdbID = details.externalIds?.imdbId
        freeOn = availability.free
        subscriptionOn = availability.subscription
        rentOrBuyOn = availability.rentOrBuy
        watchLink = availability.link
        lastRefreshed = .now

        if includeRatings || imdbScore == nil, let imdbID, !imdbID.isEmpty {
            if let scores = try? await OMDbClient.shared.scores(imdbID: imdbID) {
                imdbScore = scores.imdb
                rottenTomatoesScore = scores.rottenTomatoes
                metacriticScore = scores.metacritic
            }
        }
    }
}
