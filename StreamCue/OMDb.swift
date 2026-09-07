import Foundation

/// Ratings from OMDb, keyed off an IMDb ID.
/// Free key from omdbapi.com, 1,000 requests/day.
struct OMDbClient {
    static let shared = OMDbClient()

    struct Scores {
        var imdb: String?
        var rottenTomatoes: String?
        var metacritic: String?

        var isEmpty: Bool {
            imdb == nil && rottenTomatoes == nil && metacritic == nil
        }
    }

    func scores(imdbID: String) async throws -> Scores {
        guard !Secrets.omdbKey.isEmpty, !Secrets.omdbKey.hasPrefix("YOUR_") else {
            return Scores()
        }

        var components = URLComponents(string: "https://www.omdbapi.com/")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: Secrets.omdbKey),
            URLQueryItem(name: "i", value: imdbID)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let payload = try JSONDecoder().decode(OMDbResponse.self, from: data)

        // OMDb answers "False" with an Error field for unknown IDs.
        guard payload.response == "True" else { return Scores() }

        var scores = Scores()
        scores.imdb = payload.imdbRating.flatMap { $0 == "N/A" ? nil : $0 }
        for rating in payload.ratings ?? [] {
            switch rating.source {
            case "Rotten Tomatoes": scores.rottenTomatoes = rating.value
            case "Metacritic": scores.metacritic = rating.value
            default: break
            }
        }
        return scores
    }
}

private struct OMDbResponse: Decodable {
    let imdbRating: String?
    let ratings: [OMDbRating]?
    let response: String?

    enum CodingKeys: String, CodingKey {
        case imdbRating
        case ratings = "Ratings"
        case response = "Response"
    }
}

private struct OMDbRating: Decodable {
    let source: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }
}
