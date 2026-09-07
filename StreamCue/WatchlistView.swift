import SwiftUI
import SwiftData

struct WatchlistView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedMovie.addedAt, order: .reverse) private var movies: [TrackedMovie]

    @State private var isAdding = false
    @State private var isRefreshing = false
    @AppStorage("watchedExpanded") private var isWatchedExpanded = false
    @State private var isConfirmingClear = false
    @State private var suggestions: [MovieSearchResult] = []
    @State private var isLoadingSuggestions = false
    @State private var preview: TitlePreview?

    private var unwatched: [TrackedMovie] { movies.filter { !$0.watched } }
    private var watched: [TrackedMovie] { movies.filter(\.watched) }

    private func group(_ availability: MovieAvailability) -> [TrackedMovie] {
        unwatched.filter { $0.availability == availability }
    }

    var body: some View {
        NavigationStack {
            Group {
                if movies.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Movies")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add movie", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            Task { await refreshAll() }
                        } label: {
                            Label("Refresh all", systemImage: "arrow.clockwise")
                        }
                        .disabled(movies.isEmpty || isRefreshing)

                        if !watched.isEmpty {
                            Button(role: .destructive) {
                                isConfirmingClear = true
                            } label: {
                                Label("Delete all watched", systemImage: "trash")
                            }
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isAdding) { AddMovieView() }
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { addFromPreview(preview) }
            }
            .confirmationDialog(
                "Delete \(watched.count) watched film\(watched.count == 1 ? "" : "s")?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    for movie in watched { context.delete(movie) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task { await refreshStale() }
            .task(id: movies.count) { await loadSuggestions() }
        }
    }

    private var list: some View {
        List {
            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.secondary)
                    Text("Refreshing…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                .plainRow()
            }

            ForEach(MovieAvailability.allCases, id: \.rawValue) { availability in
                section(availability.title, group(availability), accented: availability == .free)
            }

            watchedSection

            suggestionsSection

            Color.clear.frame(height: 12).plainRow()
        }
        .themedList()
        .refreshable { await refreshAll() }
    }

    @ViewBuilder
    private var watchedSection: some View {
        if !watched.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isWatchedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isWatchedExpanded ? 90 : 0))
                    Text("Watched")
                        .font(.caption)
                        .kerning(0.5)
                        .foregroundStyle(Theme.secondary)
                    Text("\(watched.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.bottom, 2)
            .plainRow()

            if isWatchedExpanded {
                ForEach(Array(watched.enumerated()), id: \.element.id) { index, movie in
                    NavigationLink(destination: MovieDetailView(movie: movie)) {
                        MovieRow(movie: movie, showsDivider: index < watched.count - 1)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(movie)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            movie.watched = false
                        } label: {
                            Label("Unwatch", systemImage: "arrow.uturn.backward")
                        }
                        .tint(Theme.tonight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ group: [TrackedMovie], accented: Bool = false) -> some View {
        if !group.isEmpty {
            HStack(spacing: 6) {
                if accented {
                    Circle().fill(Theme.free).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.caption)
                    .kerning(0.5)
                    .foregroundStyle(accented ? Theme.free : Theme.secondary)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 2)
            .plainRow()

            ForEach(Array(group.enumerated()), id: \.element.id) { index, movie in
                NavigationLink(destination: MovieDetailView(movie: movie)) {
                    MovieRow(movie: movie, showsDivider: index < group.count - 1)
                }
                .buttonStyle(.plain)
                .plainRow()
            }
            .onDelete { offsets in
                for index in offsets { context.delete(group[index]) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            TestCard()
                .padding(.bottom, 8)
            Text("Nothing on the list")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primary)
            Text("Add a film and the app will tell you where it's streaming, and when it turns up somewhere free.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if !suggestions.isEmpty {
            HStack(spacing: 6) {
                Text("Because of your list")
                    .font(.caption)
                    .kerning(0.5)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if isLoadingSuggestions {
                    ProgressView().controlSize(.mini).tint(Theme.secondary)
                }
            }
            .padding(.top, 18)
            .plainRow()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(suggestions) { movie in
                        SuggestionTile(movie: movie) {
                            preview = TitlePreview(
                                movie,
                                isTracked: movies.contains { $0.tmdbID == movie.id }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    private func addFromPreview(_ preview: TitlePreview) {
        guard !movies.contains(where: { $0.tmdbID == preview.id }) else { return }
        let movie = Library.addMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
        suggestions.removeAll { $0.id == preview.id }
        Task { try? await movie.refresh() }
    }

    private func add(_ result: MovieSearchResult) {
        let movie = Library.addMovie(
                tmdbID: result.id,
                title: result.title,
                posterPath: result.posterPath,
                context: context
            )
        suggestions.removeAll { $0.id == result.id }
        Task { try? await movie.refresh() }
    }

    /// Fans out to TMDB's per-movie recommendations for the films most recently
    /// added, then ranks by how many of them suggested the same title.
    private func loadSuggestions() async {
        let seeds = Array(movies.prefix(6)).map(\.tmdbID)
        guard !seeds.isEmpty else {
            suggestions = []
            return
        }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        let alreadyTracked = Set(movies.map(\.tmdbID))
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
        suggestions = Array(ranked.prefix(20).map(\.result))
    }

    private func refreshAll() async {
        isRefreshing = true
        for movie in movies {
            try? await movie.refresh()
        }
        isRefreshing = false
    }

    private func refreshStale() async {
        let stale = movies.filter(\.isStale)
        guard !stale.isEmpty else { return }
        isRefreshing = true
        for movie in stale {
            try? await movie.refresh(includeRatings: false)
        }
        isRefreshing = false
    }
}

// MARK: - Row

struct MovieRow: View {
    let movie: TrackedMovie
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Poster(path: movie.posterPath, width: 34, height: 51, radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.system(size: 15))
                        .foregroundStyle(movie.watched ? Theme.secondary : Theme.primary)
                        .lineLimit(1)
                    Text(movie.subtitle)
                        .font(.footnote)
                        .foregroundStyle(movie.availability == .free ? Theme.free : Theme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let score = movie.primaryScore {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(score.0)
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primary)
                        Text(score.1)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .padding(.vertical, 8)
            .opacity(movie.watched ? 0.6 : 1)

            if showsDivider {
                Rectangle().fill(Theme.divider).frame(height: 0.5)
            }
        }
    }
}

// MARK: - Add

struct AddMovieView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tracked: [TrackedMovie]

    @State private var query = ""
    @State private var results: [MovieSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(results) { result in
                    Button {
                        add(result)
                    } label: {
                        HStack(spacing: 12) {
                            Poster(path: result.posterPath, width: 34, height: 51, radius: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundStyle(Theme.primary)
                                if let year = result.year {
                                    Text(year)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            Spacer()
                            if isTracked(result.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    .disabled(isTracked(result.id))
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "Find a film",
                        systemImage: "magnifyingglass",
                        description: Text("Type a title and hit search.")
                    )
                }
            }
            .searchable(text: $query, prompt: "Film title")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Add a film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func isTracked(_ id: Int) -> Bool {
        tracked.contains { $0.tmdbID == id }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await TMDBClient.shared.searchMovies(query)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
    }

    private func add(_ result: MovieSearchResult) {
        let movie = Library.addMovie(
                tmdbID: result.id,
                title: result.title,
                posterPath: result.posterPath,
                context: context
            )
        Task { try? await movie.refresh() }
        dismiss()
    }
}

// MARK: - Detail

struct MovieDetailView: View {
    @Bindable var movie: TrackedMovie

    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Poster(path: movie.posterPath, width: 90, height: 135, radius: 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(movie.title).font(.title3.bold())
                        Text(movie.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }

            if !movie.overview.isEmpty {
                Section {
                    Text(movie.overview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }

            if movie.hasAnyRating {
                Section("Ratings") {
                    HStack(spacing: 22) {
                        if let imdb = movie.imdbScore { ScoreBadge(label: "IMDb", value: imdb) }
                        if let rt = movie.rottenTomatoesScore { ScoreBadge(label: "Rotten Tomatoes", value: rt) }
                        if let mc = movie.metacriticScore { ScoreBadge(label: "Metacritic", value: mc) }
                        if let tmdb = movie.tmdbScore, tmdb > 0 {
                            ScoreBadge(label: "TMDB", value: String(format: "%.1f", tmdb))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Watched", isOn: $movie.watched)
                    .tint(Theme.free)
            }

            if !movie.freeOn.isEmpty {
                Section("Free") { ForEach(movie.freeOn, id: \.self, content: Text.init) }
            }
            if !movie.subscriptionOn.isEmpty {
                Section("With a subscription") { ForEach(movie.subscriptionOn, id: \.self, content: Text.init) }
            }
            if !movie.rentOrBuyOn.isEmpty {
                Section("Rent or buy") { ForEach(movie.rentOrBuyOn, id: \.self, content: Text.init) }
            }
            if movie.availability == .unavailable {
                Section("Where to watch") {
                    Text("Nothing listed in \(AppSettings.region) yet.")
                        .foregroundStyle(Theme.secondary)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                Task { await refresh() }
            } label: {
                if isRefreshing {
                    ProgressView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
        }
        .task {
            if movie.lastRefreshed == nil { await refresh() }
        }
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        do {
            try await movie.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }
}

// MARK: - Suggestion tile

struct SuggestionTile: View {
    let movie: MovieSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Poster(path: movie.posterPath, width: 92, height: 138, radius: 6)
                    Image(systemName: "info.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.primary, .black.opacity(0.55))
                        .padding(5)
                }
                Text(movie.title)
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let year = movie.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
    }
}
