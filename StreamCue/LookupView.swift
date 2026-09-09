import SwiftUI
import SwiftData

/// Find things by who made them: a person's filmography, or a studio's
/// catalogue. Both land on the same preview sheet as everywhere else.
struct LookupView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case titles = "Titles"
        case people = "People"
        case studios = "Studios"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var trackedShows: [TrackedShow]
    @Query private var trackedMovies: [TrackedMovie]

    @State private var mode: Mode = .titles
    @State private var query = ""
    @State private var people: [PersonResult] = []
    @State private var companies: [CompanyResult] = []
    @State private var titles: [CatalogItem] = []
    @State private var preview: TitlePreview?
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    if mode == .titles {
                        ForEach(titles) { item in
                            Button {
                                preview = TitlePreview(item, isTracked: isTracked(item))
                            } label: {
                                HStack(spacing: 12) {
                                    Poster(
                                        path: item.posterPath,
                                        width: 34,
                                        height: 51,
                                        radius: 4
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.primary)
                                            .lineLimit(1)
                                        Text(
                                            [item.kind == .tv ? "Show" : "Film", item.year]
                                                .compactMap { $0 }
                                                .joined(separator: " · ")
                                        )
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    if isTracked(item) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.free)
                                    }
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else if mode == .people {
                        ForEach(people) { person in
                            NavigationLink {
                                CatalogView(
                                    title: person.name,
                                    source: .person(person.id)
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    ProfilePhoto(path: person.profilePath)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.primary)
                                        if !person.summary.isEmpty {
                                            Text(person.summary)
                                                .font(.footnote)
                                                .foregroundStyle(Theme.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } else {
                        ForEach(companies) { company in
                            NavigationLink {
                                CatalogView(
                                    title: company.name,
                                    source: .company(company.id)
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    ServiceLogo(path: company.logoPath, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(company.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.primary)
                                        if let country = company.originCountry, !country.isEmpty {
                                            Text(country)
                                                .font(.footnote)
                                                .foregroundStyle(Theme.tertiary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .overlay { placeholder }
            }
            .background(Theme.background)
            .searchable(text: $query, prompt: searchPrompt)
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: mode) { _, _ in
                hasSearched = false
                Task { await search() }
            }
            .navigationTitle("Look up")
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { add(preview) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var searchPrompt: String {
        switch mode {
        case .titles: return "Show or film"
        case .people: return "Name"
        case .studios: return "Studio or network"
        }
    }

    private func isTracked(_ item: CatalogItem) -> Bool {
        switch item.kind {
        case .tv: return trackedShows.contains { $0.tmdbID == item.tmdbID }
        case .movies: return trackedMovies.contains { $0.tmdbID == item.tmdbID }
        }
    }

    private func add(_ preview: TitlePreview) {
        switch preview.kind {
        case .tv:
            let show = Library.addShow(
                tmdbID: preview.id,
                name: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await show.refresh() }
        case .movies:
            let movie = Library.addMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await movie.refresh() }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        let isEmpty: Bool = {
            switch mode {
            case .titles: return titles.isEmpty
            case .people: return people.isEmpty
            case .studios: return companies.isEmpty
            }
        }()
        if isSearching {
            ProgressView().tint(Theme.secondary)
        } else if isEmpty {
            ContentUnavailableView(
                hasSearched ? "Nothing found" : emptyTitle,
                systemImage: emptyIcon,
                description: Text(hasSearched ? "Try a different spelling." : emptyMessage)
            )
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .titles: return "Search for a title"
        case .people: return "Search for a person"
        case .studios: return "Search for a studio"
        }
    }

    private var emptyIcon: String {
        switch mode {
        case .titles: return "magnifyingglass"
        case .people: return "person.crop.circle"
        case .studios: return "building.2"
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .titles:
            return "Shows and films together — tap one to see what it is before adding it."
        case .people:
            return "An actor, a director, a writer — then browse what they've worked on."
        case .studios:
            return "Studio Ghibli, A24, Aardman — then browse their catalogue."
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            people = []
            companies = []
            titles = []
            return
        }

        isSearching = true
        errorMessage = nil
        defer {
            isSearching = false
            hasSearched = true
        }

        do {
            switch mode {
            case .titles:
                // Both kinds at once, merged by popularity so the obvious
                // match surfaces whether it's a show or a film.
                async let series = TMDBClient.shared.searchShows(trimmed)
                async let films = TMDBClient.shared.searchMovies(trimmed)
                let merged = ((try? await series) ?? []).map(CatalogItem.init)
                    + ((try? await films) ?? []).map(CatalogItem.init)
                titles = merged.sorted { $0.popularity > $1.popularity }
            case .people:
                people = try await TMDBClient.shared.searchPeople(trimmed)
            case .studios:
                companies = try await TMDBClient.shared.searchCompanies(trimmed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Catalogue

/// A grid of titles from one source, with the usual tracked and ignored
/// filtering applied.
struct CatalogView: View {
    enum Source {
        case person(Int)
        case company(Int)
    }

    let title: String
    let source: Source

    @Environment(\.modelContext) private var context
    @Query private var shows: [TrackedShow]
    @Query private var movies: [TrackedMovie]
    @Query private var ignored: [IgnoredTitle]

    @State private var items: [CatalogItem] = []
    @State private var roles: [String: String] = [:]
    @State private var isLoading = true
    @State private var preview: TitlePreview?
    @State private var filter: KindFilter = .all

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tv = "TV"
        case movies = "Films"
        var id: String { rawValue }
    }

    private var visible: [CatalogItem] {
        let hiddenShows = ignored.ids(for: .tv)
        let hiddenFilms = ignored.ids(for: .movies)
        return items.filter { item in
            switch filter {
            case .all: break
            case .tv: if item.kind != .tv { return false }
            case .movies: if item.kind != .movies { return false }
            }
            let hidden = item.kind == .tv ? hiddenShows : hiddenFilms
            return !hidden.contains(item.tmdbID)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            Picker("Kind", selection: $filter) {
                ForEach(KindFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visible) { item in
                    Button {
                        preview = TitlePreview(item, isTracked: isTracked(item))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                Poster(
                                    path: item.posterPath,
                                    width: 104,
                                    height: 156,
                                    radius: 7
                                )
                                if isTracked(item) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Theme.free)
                                        .padding(5)
                                }
                            }
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let detail = roles[item.id] ?? item.year {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 104)
                        .opacity(isTracked(item) ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .overlay {
            if isLoading {
                ProgressView().tint(Theme.secondary)
            } else if visible.isEmpty {
                ContentUnavailableView(
                    "Nothing to show",
                    systemImage: "film",
                    description: Text("No titles here for that filter.")
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { preview in
            TitlePreviewSheet(preview: preview) { add(preview) }
        }
        .task { await load() }
    }

    private func isTracked(_ item: CatalogItem) -> Bool {
        switch item.kind {
        case .tv: return shows.contains { $0.tmdbID == item.tmdbID }
        case .movies: return movies.contains { $0.tmdbID == item.tmdbID }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        switch source {
        case .person(let id):
            let credits = (try? await TMDBClient.shared.credits(forPersonID: id)) ?? []
            var built: [CatalogItem] = []
            var roleMap: [String: String] = [:]
            for credit in credits {
                guard let title = credit.displayTitle else { continue }
                let item = CatalogItem(
                    tmdbID: credit.tmdbID,
                    kind: credit.kind,
                    title: title,
                    posterPath: credit.posterPath,
                    overview: credit.overview ?? "",
                    score: credit.score,
                    year: credit.year
                )
                built.append(item)
                if let role = credit.role { roleMap[item.id] = role }
            }
            items = built
            roles = roleMap

        case .company(let id):
            async let films = TMDBClient.shared.movies(fromCompanyID: id)
            async let series = TMDBClient.shared.shows(fromCompanyID: id)
            let filmItems = ((try? await films) ?? []).map(CatalogItem.init)
            let showItems = ((try? await series) ?? []).map(CatalogItem.init)
            items = filmItems + showItems
            roles = [:]
        }
    }

    private func add(_ preview: TitlePreview) {
        switch preview.kind {
        case .tv:
            let show = Library.addShow(
                tmdbID: preview.id,
                name: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await show.refresh() }
        case .movies:
            let movie = Library.addMovie(
                tmdbID: preview.id,
                title: preview.title,
                posterPath: preview.posterPath,
                context: context
            )
            Task { try? await movie.refresh() }
        }
    }
}

// MARK: - Shared

struct ProfilePhoto: View {
    let path: String?
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: TMDBImage.profile(path)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Rectangle().fill(Theme.posterWell)
                Image(systemName: "person.fill")
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
