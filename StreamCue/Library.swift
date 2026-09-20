import Foundation
import SwiftData

/// Every insert goes through here. With CloudKit in the picture there are no
/// unique constraints on the models, so uniqueness has to be enforced by
/// checking first — and, once two devices are syncing, by merging duplicates
/// that slip through while one of them was offline.
@MainActor
enum Library {

    // MARK: - Adding

    /// Returns the existing record if the show is already tracked, so callers
    /// can't create a second copy.
    @discardableResult
    static func addShow(
        tmdbID: Int,
        name: String,
        posterPath: String?,
        context: ModelContext
    ) -> TrackedShow {
        if let existing = show(tmdbID: tmdbID, context: context) {
            return existing
        }
        let show = TrackedShow(tmdbID: tmdbID, name: name, posterPath: posterPath)
        context.insert(show)
        return show
    }

    @discardableResult
    static func addMovie(
        tmdbID: Int,
        title: String,
        posterPath: String?,
        context: ModelContext
    ) -> TrackedMovie {
        if let existing = movie(tmdbID: tmdbID, context: context) {
            return existing
        }
        let movie = TrackedMovie(tmdbID: tmdbID, title: title, posterPath: posterPath)
        context.insert(movie)
        return movie
    }

    // MARK: - Removing

    /// Deleting a show that's also on the household list needs to mark it
    /// ignored too — otherwise the next household sync sees it's missing
    /// from the personal list and just re-adds it right back.
    static func removeShow(_ show: TrackedShow, wasShared: Bool, context: ModelContext) {
        if wasShared {
            ignore(tmdbID: show.tmdbID, kind: .tv, title: show.name, posterPath: show.posterPath, context: context)
        }
        EpisodeSync.removeAll(forShowID: show.tmdbID, context: context)
        context.delete(show)
    }

    static func removeMovie(_ movie: TrackedMovie, wasShared: Bool, context: ModelContext) {
        if wasShared {
            ignore(tmdbID: movie.tmdbID, kind: .movies, title: movie.title, posterPath: movie.posterPath, context: context)
        }
        context.delete(movie)
    }

    // MARK: - Lookups

    static func show(tmdbID: Int, context: ModelContext) -> TrackedShow? {
        var descriptor = FetchDescriptor<TrackedShow>(
            predicate: #Predicate { $0.tmdbID == tmdbID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func movie(tmdbID: Int, context: ModelContext) -> TrackedMovie? {
        var descriptor = FetchDescriptor<TrackedMovie>(
            predicate: #Predicate { $0.tmdbID == tmdbID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Ignoring

    static func ignore(
        tmdbID: Int,
        kind: MediaKind,
        title: String,
        posterPath: String?,
        context: ModelContext
    ) {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<IgnoredTitle>(
            predicate: #Predicate { $0.tmdbID == tmdbID && $0.kindRaw == kindRaw }
        )
        descriptor.fetchLimit = 1
        guard ((try? context.fetch(descriptor)) ?? []).isEmpty else { return }

        context.insert(IgnoredTitle(
            tmdbID: tmdbID,
            kind: kind,
            title: title,
            posterPath: posterPath
        ))
    }

    static func isIgnored(tmdbID: Int, kind: MediaKind, context: ModelContext) -> Bool {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<IgnoredTitle>(
            predicate: #Predicate { $0.tmdbID == tmdbID && $0.kindRaw == kindRaw }
        )
        descriptor.fetchLimit = 1
        return !(((try? context.fetch(descriptor)) ?? []).isEmpty)
    }

    // MARK: - Merging

    /// Collapses duplicate records, keeping the oldest of each and folding in
    /// anything the newer copies knew that it didn't. Harmless to run now;
    /// necessary once two devices can insert the same title while offline.
    static func deduplicate(context: ModelContext) {
        mergeShows(context: context)
        mergeMovies(context: context)
        mergeEpisodes(context: context)
        mergeIgnored(context: context)
    }

    private static func mergeShows(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<TrackedShow>())) ?? []
        for (_, group) in Dictionary(grouping: all, by: \.tmdbID) where group.count > 1 {
            let sorted = group.sorted { $0.addedAt < $1.addedAt }
            guard let keeper = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                // A reminder on either copy counts.
                if keeper.reminderID == nil { keeper.reminderID = duplicate.reminderID }
                if keeper.lastRefreshed == nil { keeper.lastRefreshed = duplicate.lastRefreshed }
                // Watched wins: if either person marked it seen, it's seen.
                if duplicate.watched { keeper.watched = true }
                context.delete(duplicate)
            }
        }
    }

    private static func mergeMovies(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<TrackedMovie>())) ?? []
        for (_, group) in Dictionary(grouping: all, by: \.tmdbID) where group.count > 1 {
            let sorted = group.sorted { $0.addedAt < $1.addedAt }
            guard let keeper = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                // Watched wins: if either person marked it seen, it's seen.
                if duplicate.watched { keeper.watched = true }
                if keeper.lastRefreshed == nil { keeper.lastRefreshed = duplicate.lastRefreshed }
                context.delete(duplicate)
            }
        }
    }

    private static func mergeIgnored(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<IgnoredTitle>())) ?? []
        let grouped = Dictionary(grouping: all) { "\($0.kindRaw)-\($0.tmdbID)" }
        for (_, group) in grouped where group.count > 1 {
            for duplicate in group.sorted(by: { $0.addedAt < $1.addedAt }).dropFirst() {
                context.delete(duplicate)
            }
        }
    }

    private static func mergeEpisodes(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<PendingEpisode>())) ?? []
        for (_, group) in Dictionary(grouping: all, by: \.key) where group.count > 1 {
            let sorted = group.sorted { $0.addedAt < $1.addedAt }
            guard let keeper = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                // Actioned on either device counts as actioned.
                if duplicate.watched { keeper.watched = true }
                if duplicate.dismissed { keeper.dismissed = true }
                context.delete(duplicate)
            }
        }
    }
}
