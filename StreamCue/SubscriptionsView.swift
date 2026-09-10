import SwiftUI
import SwiftData

/// The services you pay for, stored as "id|name" lines so both halves survive
/// without a second model.
enum Subscriptions {
    static let key = "mySubscriptions"

    struct Service: Identifiable, Hashable {
        let id: Int
        let name: String
        var logoPath: String?
    }

    static func decode(_ raw: String) -> [Service] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, let id = Int(parts[0]) else { return nil }
            let logo = parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
            return Service(id: id, name: String(parts[1]), logoPath: logo)
        }
    }

    static func encode(_ services: [Service]) -> String {
        services
            .map { "\($0.id)|\($0.name)|\($0.logoPath ?? "")" }
            .joined(separator: "\n")
    }
}

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query private var shows: [TrackedShow]
    @Query private var movies: [TrackedMovie]
    @Query private var ignored: [IgnoredTitle]

    @AppStorage(Subscriptions.key) private var raw = ""
    @AppStorage(AppSettings.regionKey) private var region = "US"

    @State private var isPicking = false
    @State private var picks: [Int: [TVSearchResult]] = [:]
    @State private var moviePicks: [Int: [MovieSearchResult]] = [:]
    @State private var isLoading = false
    @State private var preview: TitlePreview?

    private var services: [Subscriptions.Service] {
        Subscriptions.decode(raw)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The three genres that show up most across the tracked shows.
    private var topGenres: [Int] {
        var counts: [Int: Int] = [:]
        for show in shows {
            for genre in show.genreIDs { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    /// Movie genres are a separate ID space from TV genres in TMDB.
    private var topMovieGenres: [Int] {
        var counts: [Int: Int] = [:]
        for movie in movies {
            for genre in movie.genreIDs { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    private var trackedIDs: Set<Int> { Set(shows.map(\.tmdbID)) }
    private var trackedMovieIDs: Set<Int> { Set(movies.map(\.tmdbID)) }

    var body: some View {
        NavigationStack {
            Group {
                if services.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("My subscriptions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPicking = true
                    } label: {
                        Label("Choose services", systemImage: "checklist")
                    }
                }
            }
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { addFromPreview(preview) }
            }
            .sheet(isPresented: $isPicking) {
                ServicePickerView(selected: services) { chosen in
                    raw = Subscriptions.encode(chosen)
                }
            }
            .task(id: raw) { await loadPicks() }
            .task(id: region) { await loadPicks() }
        }
    }

    private var list: some View {
        List {
            ForEach(services) { service in
                HStack(spacing: 10) {
                    ServiceLogo(path: service.logoPath, size: 28)
                    Text(service.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    Spacer()
                    if isLoading && picks[service.id] == nil {
                        ProgressView().controlSize(.mini).tint(Theme.secondary)
                    }
                }
                .padding(.top, 18)
                .plainRow()

                if case let results = showPicks(service.id), !results.isEmpty {
                    stripLabel("Shows")
                    strip {
                        ForEach(results) { show in
                            SuggestionPoster(
                                title: show.name,
                                posterPath: show.posterPath,
                                caption: show.score
                            ) {
                                preview = TitlePreview(
                                    show,
                                    isTracked: trackedIDs.contains(show.id)
                                )
                            }
                        }
                    }
                }

                if case let results = filmPicks(service.id), !results.isEmpty {
                    stripLabel("Films")
                    strip {
                        ForEach(results) { movie in
                            SuggestionPoster(
                                title: movie.title,
                                posterPath: movie.posterPath,
                                caption: movie.year
                            ) {
                                preview = TitlePreview(
                                    movie,
                                    isTracked: trackedMovieIDs.contains(movie.id)
                                )
                            }
                        }
                    }
                }

                if !isLoading,
                   showPicks(service.id).isEmpty,
                   filmPicks(service.id).isEmpty {
                    Text("Nothing new to suggest here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 6)
                        .plainRow()
                }
            }

            Color.clear.frame(height: 16).plainRow()
        }
        .themedList()
        .refreshable { await loadPicks(force: true) }
    }

    private func showPicks(_ serviceID: Int) -> [TVSearchResult] {
        let hidden = ignored.ids(for: .tv)
        return (picks[serviceID] ?? []).filter { !hidden.contains($0.id) }
    }

    private func filmPicks(_ serviceID: Int) -> [MovieSearchResult] {
        let hidden = ignored.ids(for: .movies)
        return (moviePicks[serviceID] ?? []).filter { !hidden.contains($0.id) }
    }

    private func stripLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .kerning(0.4)
            .foregroundStyle(Theme.tertiary)
            .padding(.top, 10)
            .plainRow()
    }

    private func strip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            TestCard()
                .padding(.bottom, 8)
            Text("No services picked")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primary)
            Text("Tell the app what you subscribe to and it'll suggest shows on each one, based on what you already watch.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button("Choose services") { isPicking = true }
                .font(.subheadline)
                .foregroundStyle(Theme.tonight)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addFromPreview(_ preview: TitlePreview) {
        switch preview.kind {
        case .tv:
            guard !trackedIDs.contains(preview.id) else { return }
            let show = Library.addShow(
                tmdbID: preview.id,
                name: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            for key in picks.keys { picks[key]?.removeAll { $0.id == preview.id } }
            Task { try? await show.refresh() }
        case .movies:
            guard !trackedMovieIDs.contains(preview.id) else { return }
            let movie = Library.addMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            for key in moviePicks.keys { moviePicks[key]?.removeAll { $0.id == preview.id } }
            Task { try? await movie.refresh() }
        }
    }

    private func add(_ result: TVSearchResult) {
        guard !trackedIDs.contains(result.id) else { return }
        let show = Library.addShow(
                tmdbID: result.id,
                name: result.name,
                posterPath: result.posterPath,
                context: context
            )
        for key in picks.keys {
            picks[key]?.removeAll { $0.id == result.id }
        }
        Task { try? await show.refresh() }
    }

    private func add(_ result: MovieSearchResult) {
        guard !trackedMovieIDs.contains(result.id) else { return }
        let movie = Library.addMovie(
                tmdbID: result.id,
                title: result.title,
                posterPath: result.posterPath,
                context: context
            )
        for key in moviePicks.keys {
            moviePicks[key]?.removeAll { $0.id == result.id }
        }
        Task { try? await movie.refresh() }
    }

    private func loadPicks(force: Bool = false) async {
        let services = self.services
        guard !services.isEmpty else {
            picks = [:]
            moviePicks = [:]
            return
        }
        if force {
            picks = [:]
            moviePicks = [:]
        }

        isLoading = true
        defer { isLoading = false }

        let showGenres = topGenres
        let movieGenres = topMovieGenres
        let excludedShows = trackedIDs
        let excludedMovies = trackedMovieIDs

        await withTaskGroup(of: (Int, [TVSearchResult]).self) { group in
            for service in services where force || picks[service.id] == nil {
                group.addTask {
                    let results = (try? await TMDBClient.shared.discoverShows(
                        providerID: service.id,
                        genres: showGenres
                    )) ?? []
                    return (service.id, results)
                }
            }
            for await (id, results) in group {
                picks[id] = Array(results.filter { !excludedShows.contains($0.id) }.prefix(15))
            }
        }

        await withTaskGroup(of: (Int, [MovieSearchResult]).self) { group in
            for service in services where force || moviePicks[service.id] == nil {
                group.addTask {
                    let results = (try? await TMDBClient.shared.discoverMovies(
                        providerID: service.id,
                        genres: movieGenres
                    )) ?? []
                    return (service.id, results)
                }
            }
            for await (id, results) in group {
                moviePicks[id] = Array(results.filter { !excludedMovies.contains($0.id) }.prefix(15))
            }
        }
    }
}

// MARK: - Service picker

struct ServicePickerView: View {
    let selected: [Subscriptions.Service]
    let onSave: ([Subscriptions.Service]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var all: [ProviderInfo] = []
    @State private var chosen: Set<Int>
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        selected: [Subscriptions.Service],
        onSave: @escaping ([Subscriptions.Service]) -> Void
    ) {
        self.selected = selected
        self.onSave = onSave
        _chosen = State(initialValue: Set(selected.map(\.id)))
    }

    private var filtered: [ProviderInfo] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.providerName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(filtered) { provider in
                    Button {
                        toggle(provider.providerId)
                    } label: {
                        HStack(spacing: 10) {
                            ServiceLogo(path: provider.logoPath, size: 28)
                            Text(provider.providerName)
                                .foregroundStyle(Theme.primary)
                            Spacer()
                            if chosen.contains(provider.providerId) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.free)
                            }
                        }
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .searchable(text: $query, prompt: "Service name")
            .navigationTitle("Your services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let services = all
                            .filter { chosen.contains($0.providerId) }
                            .map {
                                Subscriptions.Service(
                                    id: $0.providerId,
                                    name: $0.providerName,
                                    logoPath: $0.logoPath
                                )
                            }
                        onSave(services)
                        dismiss()
                    }
                }
            }
            .task { await load() }
        }
    }

    private func toggle(_ id: Int) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            all = try await TMDBClient.shared.availableProviders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shared bits

struct ServiceLogo: View {
    let path: String?
    var size: CGFloat = 28

    var body: some View {
        CachedImage(url: TMDBImage.logo(path)) {
            RoundedRectangle(cornerRadius: 6).fill(Theme.posterWell)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SuggestionPoster: View {
    let title: String
    let posterPath: String?
    var caption: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Poster(path: posterPath, width: 92, height: 138, radius: 6)
                    Image(systemName: "info.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.primary, .black.opacity(0.55))
                        .padding(5)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
    }
}
