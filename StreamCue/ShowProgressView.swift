import SwiftUI
import SwiftData

/// Full per-episode watched checklist for an ended/canceled show —
/// EpisodeSync only ever looks at the last 30 days, so a show with nothing
/// left to air has no "recent" episode to catch up from. This fetches each
/// season's episode list from TMDB on demand and cross-references it
/// against the sparse `WatchedEpisode` records kept locally, rather than
/// persisting a row for every episode up front.
struct ShowProgressView: View {
    let show: TrackedShow

    @Environment(\.modelContext) private var context
    @Query private var watchedEpisodes: [WatchedEpisode]

    @State private var selectedSeason: Int
    @State private var episodes: [TVEpisode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(show: TrackedShow) {
        self.show = show
        let id = show.tmdbID
        _watchedEpisodes = Query(filter: #Predicate<WatchedEpisode> { $0.showID == id })
        _selectedSeason = State(initialValue: max(show.lastAiredSeason ?? show.totalSeasonCount ?? 1, 1))
    }

    private var seasonCount: Int {
        max(show.totalSeasonCount ?? show.lastAiredSeason ?? 1, 1)
    }

    private var watchedKeys: Set<String> {
        Set(watchedEpisodes.map(\.key))
    }

    private var episodeNumbersInSeason: [Int] {
        episodes.compactMap(\.episodeNumber)
    }

    private var isSeasonFullyWatched: Bool {
        !episodeNumbersInSeason.isEmpty && episodeNumbersInSeason.allSatisfy {
            watchedKeys.contains(WatchedEpisode.makeKey(showID: show.tmdbID, season: selectedSeason, episode: $0))
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Watched") {
                    if let total = show.totalEpisodeCount {
                        Text("\(watchedEpisodes.count) of \(total)")
                    } else {
                        Text("\(watchedEpisodes.count)")
                    }
                }
                Picker("Season", selection: $selectedSeason) {
                    ForEach(1...seasonCount, id: \.self) { number in
                        Text("Season \(number)").tag(number)
                    }
                }
            }

            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if episodes.isEmpty {
                    Text("No episodes listed for this season.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(episodeNumbersInSeason, id: \.self) { number in
                        if let episode = episodes.first(where: { $0.episodeNumber == number }) {
                            episodeRow(episode, number: number)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Episodes")
                    Spacer()
                    if !episodeNumbersInSeason.isEmpty {
                        Button(isSeasonFullyWatched ? "Clear season" : "Mark season watched") {
                            toggleSeason()
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedSeason) { await loadSeason() }
    }

    private func episodeRow(_ episode: TVEpisode, number: Int) -> some View {
        let key = WatchedEpisode.makeKey(showID: show.tmdbID, season: selectedSeason, episode: number)
        let watched = watchedKeys.contains(key)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.label ?? "Episode \(number)")
                    .lineLimit(1)
                if let airDate = TMDBDate.parse(episode.airDate) {
                    Text(airDate.formatted(.dateTime.month().day().year()))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 4)
            Button {
                toggleWatched(number: number, key: key)
            } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(watched ? Theme.free : Theme.tertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(watched ? "Mark unwatched" : "Mark watched")
        }
    }

    @MainActor
    private func loadSeason() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let season = try await TMDBClient.shared.season(showID: show.tmdbID, number: selectedSeason)
            episodes = season.episodes
        } catch {
            episodes = []
            errorMessage = "Couldn't load this season."
        }
    }

    private func toggleWatched(number: Int, key: String) {
        if let existing = watchedEpisodes.first(where: { $0.key == key }) {
            context.delete(existing)
        } else {
            context.insert(WatchedEpisode(showID: show.tmdbID, seasonNumber: selectedSeason, episodeNumber: number))
        }
    }

    private func toggleSeason() {
        let markingWatched = !isSeasonFullyWatched
        for number in episodeNumbersInSeason {
            let key = WatchedEpisode.makeKey(showID: show.tmdbID, season: selectedSeason, episode: number)
            let existing = watchedEpisodes.first { $0.key == key }
            if markingWatched {
                if existing == nil {
                    context.insert(WatchedEpisode(showID: show.tmdbID, seasonNumber: selectedSeason, episodeNumber: number))
                }
            } else if let existing {
                context.delete(existing)
            }
        }
    }
}
