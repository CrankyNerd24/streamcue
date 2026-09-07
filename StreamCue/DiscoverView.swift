import SwiftUI
import SwiftData

/// Providers aren't in TMDB's feed responses, so each title needs its own
/// lookup. Cached per session and fetched only for tiles that scroll into view.
@MainActor
@Observable
final class ProviderCache {
    struct Badge {
        let name: String
        let isFree: Bool
    }

    private var badges: [String: Badge?] = [:]
    private var inFlight: Set<String> = []

    private func key(_ id: Int, _ kind: MediaKind) -> String { "\(kind.rawValue)-\(id)" }

    func badge(for id: Int, kind: MediaKind) -> Badge? {
        badges[key(id, kind)] ?? nil
    }

    func load(_ id: Int, kind: MediaKind) async {
        let cacheKey = key(id, kind)
        guard badges[cacheKey] == nil, !inFlight.contains(cacheKey) else { return }
        inFlight.insert(cacheKey)
        defer { inFlight.remove(cacheKey) }

        let availability: Availability?
        switch kind {
        case .tv:
            availability = try? await TMDBClient.shared.availability(id: id)
        case .movies:
            availability = try? await TMDBClient.shared.movieAvailability(id: id)
        }
        guard let availability else { return }

        if let free = availability.free.first {
            badges[cacheKey] = Badge(name: free, isFree: true)
        } else if let subscription = availability.subscription.first {
            badges[cacheKey] = Badge(name: subscription, isFree: false)
        } else {
            badges[cacheKey] = Badge?.none
        }
    }
}

struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedShow.addedAt, order: .reverse) private var tracked: [TrackedShow]
    @Query(sort: \TrackedMovie.addedAt, order: .reverse) private var trackedMovies: [TrackedMovie]

    @State private var kind: MediaKind = .tv
    @State private var feed: DiscoverFeed = .forYou
    @State private var showResults: [TVSearchResult] = []
    @State private var movieResults: [MovieSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var providers = ProviderCache()
    @State private var preview: TitlePreview?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var isEmptyForYou: Bool {
        feed == .forYou && (kind == .tv ? tracked.isEmpty : trackedMovies.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Picker("Kind", selection: $kind) {
                        ForEach(MediaKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Feed", selection: $feed) {
                        ForEach(DiscoverFeed.allCases) { feed in
                            Text(feed.rawValue).tag(feed)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    if kind == .tv {
                        ForEach(showResults) { show in
                            tile(
                                id: show.id,
                                title: show.name,
                                posterPath: show.posterPath,
                                score: show.score,
                                isTracked: isTracked(show.id)
                            ) {
                                preview = TitlePreview(show, isTracked: isTracked(show.id))
                            }
                        }
                    } else {
                        ForEach(movieResults) { movie in
                            tile(
                                id: movie.id,
                                title: movie.title,
                                posterPath: movie.posterPath,
                                score: movie.score,
                                isTracked: isTrackedMovie(movie.id)
                            ) {
                                preview = TitlePreview(movie, isTracked: isTrackedMovie(movie.id))
                            }
                        }
                    }
                }
                .padding()
            }
            .overlay {
                if isLoading && currentIsEmpty {
                    ProgressView()
                } else if isEmptyForYou {
                    ContentUnavailableView(
                        "Nothing to go on yet",
                        systemImage: "sparkles",
                        description: Text(
                            kind == .tv
                            ? "Track a few shows and this fills up with things like them."
                            : "Add a few films and this fills up with things like them."
                        )
                    )
                }
            }
            .navigationTitle("Discover")
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { addFromPreview(preview) }
            }
            .task(id: "\(kind.rawValue)-\(feed.rawValue)") { await load() }
            .refreshable { await load() }
        }
    }

    private var currentIsEmpty: Bool {
        kind == .tv ? showResults.isEmpty : movieResults.isEmpty
    }

    private func tile(
        id: Int,
        title: String,
        posterPath: String?,
        score: String?,
        isTracked: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        PosterTile(
            title: title,
            posterPath: posterPath,
            score: score,
            isTracked: isTracked,
            badge: providers.badge(for: id, kind: kind),
            onTap: onTap
        )
        .task { await providers.load(id, kind: kind) }
    }

    private func isTracked(_ id: Int) -> Bool {
        tracked.contains { $0.tmdbID == id }
    }

    private func isTrackedMovie(_ id: Int) -> Bool {
        trackedMovies.contains { $0.tmdbID == id }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            switch (kind, feed) {
            case (.tv, .forYou):
                showResults = await recommendedShows()
            case (.movies, .forYou):
                movieResults = await recommendedMovies()
            case (.tv, _):
                showResults = try await TMDBClient.shared.shows(in: feed)
            case (.movies, _):
                movieResults = try await TMDBClient.shared.movies(in: feed)
            }
        } catch {
            errorMessage = error.localizedDescription
            if kind == .tv { showResults = [] } else { movieResults = [] }
        }
        isLoading = false
    }

    /// Ranks by how many of your own titles recommended the same thing —
    /// something four of them point at beats something only one does.
    private func recommendedShows() async -> [TVSearchResult] {
        let seeds = tracked.prefix(8).map(\.tmdbID)
        guard !seeds.isEmpty else { return [] }
        let alreadyTracked = Set(tracked.map(\.tmdbID))

        var tally: [Int: (result: TVSearchResult, votes: Int)] = [:]
        await withTaskGroup(of: [TVSearchResult].self) { group in
            for id in seeds {
                group.addTask {
                    (try? await TMDBClient.shared.recommendations(forShowID: id)) ?? []
                }
            }
            for await batch in group {
                for item in batch where !alreadyTracked.contains(item.id) {
                    if let existing = tally[item.id] {
                        tally[item.id] = (existing.result, existing.votes + 1)
                    } else {
                        tally[item.id] = (item, 1)
                    }
                }
            }
        }

        let ranked = tally.values.sorted { left, right in
            if left.votes != right.votes { return left.votes > right.votes }
            return (left.result.voteAverage ?? 0) > (right.result.voteAverage ?? 0)
        }
        return Array(ranked.prefix(40).map(\.result))
    }

    private func recommendedMovies() async -> [MovieSearchResult] {
        let seeds = trackedMovies.prefix(8).map(\.tmdbID)
        guard !seeds.isEmpty else { return [] }
        let alreadyTracked = Set(trackedMovies.map(\.tmdbID))

        var tally: [Int: (result: MovieSearchResult, votes: Int)] = [:]
        await withTaskGroup(of: [MovieSearchResult].self) { group in
            for id in seeds {
                group.addTask {
                    (try? await TMDBClient.shared.recommendations(forMovieID: id)) ?? []
                }
            }
            for await batch in group {
                for item in batch where !alreadyTracked.contains(item.id) {
                    if let existing = tally[item.id] {
                        tally[item.id] = (existing.result, existing.votes + 1)
                    } else {
                        tally[item.id] = (item, 1)
                    }
                }
            }
        }

        let ranked = tally.values.sorted { left, right in
            if left.votes != right.votes { return left.votes > right.votes }
            return (left.result.voteAverage ?? 0) > (right.result.voteAverage ?? 0)
        }
        return Array(ranked.prefix(40).map(\.result))
    }

    // MARK: - Adding

    private func addFromPreview(_ preview: TitlePreview) {
        switch preview.kind {
        case .tv:
            guard !isTracked(preview.id) else { return }
            let show = TrackedShow(
                tmdbID: preview.id,
                name: preview.title,
                posterPath: preview.posterPath
            )
            context.insert(show)
            Task { try? await show.refresh() }
        case .movies:
            guard !isTrackedMovie(preview.id) else { return }
            let movie = TrackedMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath
            )
            context.insert(movie)
            Task { try? await movie.refresh() }
        }
    }

    private func add(_ result: TVSearchResult) {
        guard !isTracked(result.id) else { return }
        let show = TrackedShow(
            tmdbID: result.id,
            name: result.name,
            posterPath: result.posterPath
        )
        context.insert(show)
        Task { try? await show.refresh() }
    }

    private func add(_ result: MovieSearchResult) {
        guard !isTrackedMovie(result.id) else { return }
        let movie = TrackedMovie(
            tmdbID: result.id,
            title: result.title,
            posterPath: result.posterPath
        )
        context.insert(movie)
        Task { try? await movie.refresh() }
    }
}

// MARK: - Tile

struct PosterTile: View {
    let title: String
    let posterPath: String?
    let score: String?
    let isTracked: Bool
    let badge: ProviderCache.Badge?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: TMDBImage.poster(posterPath, width: 342)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Theme.posterWell)
                    }
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) {
                        if let score {
                            Text(score)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(6)
                        }
                    }

                    Image(systemName: isTracked ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isTracked ? Theme.free : .black.opacity(0.6))
                        .padding(6)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.primary)

                    if let badge {
                        Text(badge.isFree ? "Free · \(badge.name)" : badge.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(badge.isFree ? Theme.free : Theme.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isTracked ? 0.55 : 1)
    }
}
