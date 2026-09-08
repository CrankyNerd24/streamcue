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
    @Query private var ignored: [IgnoredTitle]

    @State private var kind: MediaKind = .tv
    @State private var feed: DiscoverFeed = .forYou
    @State private var showResults: [TVSearchResult] = []
    @State private var movieResults: [MovieSearchResult] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var totalPages = 1
    @State private var errorMessage: String?
    @State private var providers = ProviderCache()
    @State private var preview: TitlePreview?
    @State private var isSearchingPeople = false
    @State private var scrollOffset: CGFloat = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    /// Anything already tracked is dropped — a browse screen shouldn't show
    /// you things you've got. Computed rather than filtered at load time so
    /// adding a title removes it from the grid immediately.
    private var visibleShows: [TVSearchResult] {
        let hidden = ignored.ids(for: .tv)
        return showResults.filter { !isTracked($0.id) && !hidden.contains($0.id) }
    }

    private var visibleMovies: [MovieSearchResult] {
        let hidden = ignored.ids(for: .movies)
        return movieResults.filter { !isTrackedMovie($0.id) && !hidden.contains($0.id) }
    }

    private var isEmptyForYou: Bool {
        feed == .forYou && (kind == .tv ? tracked.isEmpty : trackedMovies.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("top")
                    .reportsScrollOffset(in: "discover")

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
                        ForEach(visibleShows) { show in
                            paginated(show.id, last: visibleShows.last?.id)
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
                        ForEach(visibleMovies) { movie in
                            paginated(movie.id, last: visibleMovies.last?.id)
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

                if isLoadingMore {
                    ProgressView()
                        .tint(Theme.secondary)
                        .padding(.bottom, 20)
                }
            }
            .overlay {
                if isLoading && currentIsEmpty {
                    ProgressView()
                } else if !isLoading && currentIsEmpty && !isEmptyForYou {
                    ContentUnavailableView(
                        "You're all caught up",
                        systemImage: "checkmark.circle",
                        description: Text("Everything here is already on your list. Try another feed.")
                    )
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
            .coordinateSpace(name: "discover")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                Task { @MainActor in scrollOffset = value }
            }
            .overlay(alignment: .bottomTrailing) {
                if scrollOffset < -800 {
                    BackToTopButton {
                        withAnimation { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: scrollOffset < -800)
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchingPeople = true
                    } label: {
                        Label("Look up", systemImage: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $isSearchingPeople) {
                LookupView()
            }
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { addFromPreview(preview) }
            }
            .task(id: "\(kind.rawValue)-\(feed.rawValue)") { await load() }
            .refreshable { await load() }
            }
        }
    }

    private var currentIsEmpty: Bool {
        kind == .tv ? visibleShows.isEmpty : visibleMovies.isEmpty
    }

    /// An invisible marker that asks for the next page when the last tile in
    /// the grid comes into view.
    @ViewBuilder
    private func paginated(_ id: Int, last: Int?) -> some View {
        if id == last {
            Color.clear
                .frame(height: 0)
                .onAppear { Task { await loadMore() } }
        }
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
        page = 1
        totalPages = 1
        do {
            switch (kind, feed) {
            case (.tv, .forYou):
                showResults = await recommendedShows()
            case (.movies, .forYou):
                movieResults = await recommendedMovies()
            case (.tv, _):
                let response = try await TMDBClient.shared.shows(in: feed, page: 1)
                showResults = response.results
                totalPages = response.totalPages
            case (.movies, _):
                let response = try await TMDBClient.shared.movies(in: feed, page: 1)
                movieResults = response.results
                totalPages = response.totalPages
            }
        } catch {
            errorMessage = error.localizedDescription
            if kind == .tv { showResults = [] } else { movieResults = [] }
        }
        isLoading = false
    }

    /// "For you" is assembled from your own list rather than fetched, so it
    /// has no pages to walk.
    private func loadMore() async {
        guard feed != .forYou,
              !isLoadingMore,
              !isLoading,
              page < totalPages,
              page < 20 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = page + 1
        do {
            switch kind {
            case .tv:
                let response = try await TMDBClient.shared.shows(in: feed, page: next)
                let known = Set(showResults.map(\.id))
                showResults += response.results.filter { !known.contains($0.id) }
                totalPages = response.totalPages
            case .movies:
                let response = try await TMDBClient.shared.movies(in: feed, page: next)
                let known = Set(movieResults.map(\.id))
                movieResults += response.results.filter { !known.contains($0.id) }
                totalPages = response.totalPages
            }
            page = next
        } catch {
            // Silent: the current page is still on screen and usable.
        }
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
            let show = Library.addShow(
                tmdbID: preview.id,
                name: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await show.refresh() }
        case .movies:
            guard !isTrackedMovie(preview.id) else { return }
            let movie = Library.addMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await movie.refresh() }
        }
    }

    private func add(_ result: TVSearchResult) {
        guard !isTracked(result.id) else { return }
        let show = Library.addShow(
                tmdbID: result.id,
                name: result.name,
                posterPath: result.posterPath,
                context: context
            )
        Task { try? await show.refresh() }
    }

    private func add(_ result: MovieSearchResult) {
        guard !isTrackedMovie(result.id) else { return }
        let movie = Library.addMovie(
                tmdbID: result.id,
                title: result.title,
                posterPath: result.posterPath,
                context: context
            )
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
