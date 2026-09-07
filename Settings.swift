import Foundation

/// User-adjustable settings. Read directly from UserDefaults so non-view code
/// (the API client, the model) can reach them without a SwiftUI environment.
enum AppSettings {
    /// nonisolated because the API client reads these off the main actor.
    nonisolated static let regionKey = "watchRegion"

    nonisolated static var region: String {
        UserDefaults.standard.string(forKey: regionKey) ?? "US"
    }
}

/// Countries TMDB carries watch-provider data for. Not exhaustive — TMDB
/// supports more, but these cover most cases without a network round trip.
enum WatchRegion {
    nonisolated static let all: [(code: String, name: String)] = [
        ("AU", "Australia"),
        ("AT", "Austria"),
        ("BE", "Belgium"),
        ("BR", "Brazil"),
        ("CA", "Canada"),
        ("DK", "Denmark"),
        ("FI", "Finland"),
        ("FR", "France"),
        ("DE", "Germany"),
        ("IN", "India"),
        ("IE", "Ireland"),
        ("IT", "Italy"),
        ("JP", "Japan"),
        ("MX", "Mexico"),
        ("NL", "Netherlands"),
        ("NZ", "New Zealand"),
        ("NO", "Norway"),
        ("PL", "Poland"),
        ("PT", "Portugal"),
        ("ZA", "South Africa"),
        ("KR", "South Korea"),
        ("ES", "Spain"),
        ("SE", "Sweden"),
        ("CH", "Switzerland"),
        ("GB", "United Kingdom"),
        ("US", "United States")
    ]

    nonisolated static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}
