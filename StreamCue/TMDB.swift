import Foundation

// MARK: - Search

struct TVSearchResponse: Decodable {
    let page: Int?
    let results: [TVSearchResult]
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}

struct TVSearchResult: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, popularity
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }

    /// Formatted TMDB score, or nil when the show has no votes yet.
    var score: String? {
        guard let voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", voteAverage)
    }

    var year: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }
}

// MARK: - Show details

struct TVDetails: Decodable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let status: String
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [Genre]?
    let nextEpisodeToAir: TVEpisode?
    let lastEpisodeToAir: TVEpisode?
    let externalIds: ExternalIDs?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, genres
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case nextEpisodeToAir = "next_episode_to_air"
        case lastEpisodeToAir = "last_episode_to_air"
        case externalIds = "external_ids"
    }
}

struct Genre: Decodable {
    let id: Int
    let name: String
}

struct SeasonDetails: Decodable {
    let episodes: [TVEpisode]
}

struct ExternalIDs: Decodable {
    let imdbId: String?

    enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
    }
}

struct TVEpisode: Decodable {
    let id: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case airDate = "air_date"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
    }

    /// "S03E07 · Episode title"
    var label: String? {
        guard let seasonNumber, let episodeNumber else { return name }
        let number = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
        guard let name, !name.isEmpty else { return number }
        return "\(number) · \(name)"
    }
}

// MARK: - Movies

struct MovieSearchResponse: Decodable {
    let page: Int?
    let results: [MovieSearchResult]
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}

struct MovieSearchResult: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, popularity
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
    }

    var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    var score: String? {
        guard let voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", voteAverage)
    }
}

struct MovieDetails: Decodable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    let status: String
    let runtime: Int?
    let voteAverage: Double?
    let genres: [Genre]?
    let externalIds: ExternalIDs?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, status, runtime, genres
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case externalIds = "external_ids"
    }
}

// MARK: - People

struct PersonSearchResponse: Decodable {
    let results: [PersonResult]
}

struct PersonResult: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?
    let knownFor: [PersonCredit]?

    enum CodingKeys: String, CodingKey {
        case id, name, popularity
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case knownFor = "known_for"
    }

    /// "Acting · Fringe, Dollhouse"
    var summary: String {
        var parts: [String] = []
        if let knownForDepartment { parts.append(knownForDepartment) }
        let titles = (knownFor ?? []).prefix(2).compactMap(\.displayTitle)
        if !titles.isEmpty { parts.append(titles.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

struct PersonCreditsResponse: Decodable {
    let cast: [PersonCredit]?
    let crew: [PersonCredit]?
}

/// One entry from a person's filmography. Covers both TV and film, so it
/// carries both `name` and `title` and picks whichever is populated.
struct PersonCredit: Decodable, Identifiable, Sendable {
    let tmdbID: Int
    let mediaType: String?
    let name: String?
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let firstAirDate: String?
    let releaseDate: String?
    let character: String?
    let job: String?

    enum CodingKeys: String, CodingKey {
        case name, title, overview, character, job, popularity
        case tmdbID = "id"
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
    }

    /// A show and a film can share a numeric id, so the list key needs both.
    var id: String { "\(mediaType ?? "?")-\(tmdbID)" }

    var kind: MediaKind { mediaType == "movie" ? .movies : .tv }

    var displayTitle: String? {
        let value = kind == .movies ? title : name
        return (value?.isEmpty ?? true) ? nil : value
    }

    var year: String? {
        let raw = kind == .movies ? releaseDate : firstAirDate
        guard let raw, raw.count >= 4 else { return nil }
        return String(raw.prefix(4))
    }

    var score: String? {
        guard let voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", voteAverage)
    }

    /// "Ellie" for cast, "Director" for crew.
    var role: String? {
        if let character, !character.isEmpty { return character }
        if let job, !job.isEmpty { return job }
        return nil
    }
}

// MARK: - Companies

struct CompanySearchResponse: Decodable {
    let results: [CompanyResult]
}

struct CompanyResult: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

// MARK: - Where to watch

struct WatchProviderResponse: Decodable {
    let results: [String: RegionProviders]
}

struct RegionProviders: Decodable {
    let link: String?
    let flatrate: [WatchProvider]?
    let free: [WatchProvider]?
    let ads: [WatchProvider]?
    let rent: [WatchProvider]?
    let buy: [WatchProvider]?
}

struct WatchProvider: Decodable {
    let providerId: Int
    let providerName: String

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
    }
}

struct ProviderListResponse: Decodable {
    let results: [ProviderInfo]
}

struct ProviderInfo: Decodable, Identifiable, Sendable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int

    var id: Int { providerId }

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

/// Flattened availability for one country.
struct Availability {
    var subscription: [String] = []   // included with a subscription you pay for
    var free: [String] = []           // genuinely free, or free with ads
    var rentOrBuy: [String] = []
    var link: String?
}

// MARK: - Errors

enum TMDBError: LocalizedError {
    case missingToken
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your TMDB read access token in Secrets.swift."
        case .http(401):
            return "TMDB rejected the token. Check it was copied in full."
        case .http(let code):
            return "TMDB returned an error (\(code))."
        }
    }
}

// MARK: - Client

struct TMDBClient: Sendable {
    static let shared = TMDBClient()

    private let base = "https://api.themoviedb.org/3"

    func searchShows(_ query: String) async throws -> [TVSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: TVSearchResponse = try await get(
            "/search/tv",
            query: [URLQueryItem(name: "query", value: trimmed)]
        )
        return response.results
    }

    func details(id: Int) async throws -> TVDetails {
        try await get(
            "/tv/\(id)",
            query: [URLQueryItem(name: "append_to_response", value: "external_ids")]
        )
    }

    func searchCompanies(_ query: String) async throws -> [CompanyResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: CompanySearchResponse = try await get(
            "/search/company",
            query: [URLQueryItem(name: "query", value: trimmed)]
        )
        return response.results
    }

    /// Films a company produced. TMDB filters server-side by company id.
    func movies(fromCompanyID id: Int, page: Int = 1) async throws -> [MovieSearchResult] {
        let response: MovieSearchResponse = try await get(
            "/discover/movie",
            query: [
                URLQueryItem(name: "with_companies", value: String(id)),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return response.results
    }

    func shows(fromCompanyID id: Int, page: Int = 1) async throws -> [TVSearchResult] {
        let response: TVSearchResponse = try await get(
            "/discover/tv",
            query: [
                URLQueryItem(name: "with_companies", value: String(id)),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return response.results
    }

    func searchPeople(_ query: String) async throws -> [PersonResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: PersonSearchResponse = try await get(
            "/search/person",
            query: [URLQueryItem(name: "query", value: trimmed)]
        )
        return response.results
    }

    /// Everything a person has been in, cast and crew, TV and film. Deduped
    /// because someone who wrote and directed the same film appears twice.
    func credits(forPersonID id: Int) async throws -> [PersonCredit] {
        let response: PersonCreditsResponse = try await get("/person/\(id)/combined_credits")
        let all = (response.cast ?? []) + (response.crew ?? [])

        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.id).inserted }

        return unique
            .filter { $0.displayTitle != nil && $0.posterPath != nil }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    func season(showID: Int, number: Int) async throws -> SeasonDetails {
        try await get("/tv/\(showID)/season/\(number)")
    }

    func availability(id: Int, region: String = AppSettings.region) async throws -> Availability {
        try await providers(path: "/tv/\(id)/watch/providers", region: region)
    }

    func movieAvailability(id: Int, region: String = AppSettings.region) async throws -> Availability {
        try await providers(path: "/movie/\(id)/watch/providers", region: region)
    }

    private func providers(path: String, region: String) async throws -> Availability {
        let response: WatchProviderResponse = try await get(path)
        guard let region = response.results[region] else { return Availability() }

        var availability = Availability()
        availability.subscription = (region.flatrate ?? []).map(\.providerName)
        availability.free = ((region.free ?? []) + (region.ads ?? [])).map(\.providerName)
        availability.rentOrBuy = ((region.rent ?? []) + (region.buy ?? [])).map(\.providerName)
        availability.link = region.link
        return availability
    }

    func searchMovies(_ query: String) async throws -> [MovieSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: MovieSearchResponse = try await get(
            "/search/movie",
            query: [URLQueryItem(name: "query", value: trimmed)]
        )
        return response.results
    }

    func movieDetails(id: Int) async throws -> MovieDetails {
        try await get(
            "/movie/\(id)",
            query: [URLQueryItem(name: "append_to_response", value: "external_ids")]
        )
    }

    // MARK: Plumbing

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard !Secrets.tmdbToken.hasPrefix("PASTE") else { throw TMDBError.missingToken }

        var components = URLComponents(string: base + path)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(Secrets.tmdbToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TMDBError.http(http.statusCode)
        }
        // No .convertFromSnakeCase here on purpose: it would also lowercase the
        // country-code keys ("US" -> "us") in the watch-providers response.
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Discover feeds

enum MediaKind: String, CaseIterable, Identifiable {
    case tv = "TV"
    case movies = "Movies"

    var id: String { rawValue }
}

enum DiscoverFeed: String, CaseIterable, Identifiable {
    case forYou = "For you"
    case trending = "Trending"
    case popular = "Popular"

    var id: String { rawValue }

    /// nil for feeds that aren't a single endpoint — "For you" is assembled
    /// from the user's own list rather than fetched.
    func path(for kind: MediaKind) -> String? {
        switch (self, kind) {
        case (.forYou, _):          return nil
        case (.trending, .tv):      return "/trending/tv/week"
        case (.trending, .movies):  return "/trending/movie/week"
        case (.popular, .tv):       return "/tv/popular"
        case (.popular, .movies):   return "/movie/popular"
        }
    }
}

extension TMDBClient {
    func shows(
        in feed: DiscoverFeed,
        page: Int = 1
    ) async throws -> (results: [TVSearchResult], totalPages: Int) {
        guard let path = feed.path(for: .tv) else { return ([], 1) }
        let response: TVSearchResponse = try await get(
            path,
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return (response.results, response.totalPages ?? 1)
    }

    func movies(
        in feed: DiscoverFeed,
        page: Int = 1
    ) async throws -> (results: [MovieSearchResult], totalPages: Int) {
        guard let path = feed.path(for: .movies) else { return ([], 1) }
        let response: MovieSearchResponse = try await get(
            path,
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return (response.results, response.totalPages ?? 1)
    }

    func recommendations(forShowID id: Int) async throws -> [TVSearchResult] {
        let response: TVSearchResponse = try await get("/tv/\(id)/recommendations")
        return response.results
    }

    /// Every streaming service TMDB tracks in a region, most prominent first.
    func availableProviders(region: String = AppSettings.region) async throws -> [ProviderInfo] {
        let response: ProviderListResponse = try await get(
            "/watch/providers/tv",
            query: [URLQueryItem(name: "watch_region", value: region)]
        )
        return response.results.sorted { $0.displayPriority < $1.displayPriority }
    }

    /// Popular shows on one service, narrowed to genres the user already
    /// watches. TMDB filters by provider server-side, so this is one request
    /// rather than a per-title availability check.
    func discoverShows(
        providerID: Int,
        genres: [Int],
        region: String = AppSettings.region
    ) async throws -> [TVSearchResult] {
        var query = [
            URLQueryItem(name: "watch_region", value: region),
            URLQueryItem(name: "with_watch_providers", value: String(providerID)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50")
        ]
        if !genres.isEmpty {
            // Pipe means "any of these" rather than "all of these".
            query.append(URLQueryItem(
                name: "with_genres",
                value: genres.map(String.init).joined(separator: "|")
            ))
        }
        let response: TVSearchResponse = try await get("/discover/tv", query: query)
        return response.results
    }

    /// Films on one service, narrowed to genres the user already watches.
    /// TMDB keys movie genres separately from TV, so these IDs come from
    /// tracked films rather than tracked shows.
    func discoverMovies(
        providerID: Int,
        genres: [Int],
        region: String = AppSettings.region
    ) async throws -> [MovieSearchResult] {
        var query = [
            URLQueryItem(name: "watch_region", value: region),
            URLQueryItem(name: "with_watch_providers", value: String(providerID)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "100")
        ]
        if !genres.isEmpty {
            query.append(URLQueryItem(
                name: "with_genres",
                value: genres.map(String.init).joined(separator: "|")
            ))
        }
        let response: MovieSearchResponse = try await get("/discover/movie", query: query)
        return response.results
    }

    func recommendations(forMovieID id: Int) async throws -> [MovieSearchResult] {
        let response: MovieSearchResponse = try await get("/movie/\(id)/recommendations")
        return response.results
    }
}

// MARK: - Dates and images

enum TMDBDate {
    /// TMDB sends a plain calendar date ("2026-09-06") with no time or zone.
    /// Parsing it as UTC lands it on the previous evening in western time
    /// zones, which breaks both the displayed date and isDateInToday. Build it
    /// in the local calendar instead, at midday so a daylight-saving shift
    /// can't drag it across a day boundary.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return Calendar.current.date(from: components)
    }
}

enum TMDBImage {
    static func poster(_ path: String?, width: Int = 342) -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w\(width)\(path)")
    }

    static func profile(_ path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    static func logo(_ path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(path)")
    }
}
