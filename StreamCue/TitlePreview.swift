import SwiftUI

/// A title you haven't tracked yet, shown before you commit to adding it.
struct TitlePreview: Identifiable {
    let id: Int
    let kind: MediaKind
    let title: String
    let posterPath: String?
    let overview: String
    let score: String?
    let subtitle: String?
    let isTracked: Bool

    init(_ show: TVSearchResult, isTracked: Bool) {
        self.id = show.id
        self.kind = .tv
        self.title = show.name
        self.posterPath = show.posterPath
        self.overview = show.overview
        self.score = show.score
        self.subtitle = show.year
        self.isTracked = isTracked
    }

    init(_ movie: MovieSearchResult, isTracked: Bool) {
        self.id = movie.id
        self.kind = .movies
        self.title = movie.title
        self.posterPath = movie.posterPath
        self.overview = movie.overview
        self.score = movie.score
        self.subtitle = movie.year
        self.isTracked = isTracked
    }
}

struct TitlePreviewSheet: View {
    let preview: TitlePreview
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var availability: Availability?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Poster(path: preview.posterPath, width: 100, height: 150, radius: 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(preview.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.primary)

                            if let subtitle = preview.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondary)
                            }

                            if let score = preview.score {
                                Text("TMDB \(score)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if preview.overview.isEmpty {
                        Text("No description available.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.tertiary)
                    } else {
                        Text(preview.overview)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }

                    availabilitySection

                    Button {
                        onAdd()
                        dismiss()
                    } label: {
                        Label(
                            preview.isTracked
                                ? "Already on your list"
                                : (preview.kind == .tv ? "Track this show" : "Add to Movies"),
                            systemImage: preview.isTracked ? "checkmark" : "plus"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .background(
                        preview.isTracked ? Theme.card : Theme.tonight,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(preview.isTracked ? Theme.secondary : .white)
                    .disabled(preview.isTracked)
                    .padding(.top, 4)

                    if !preview.isTracked {
                        Button {
                            Library.ignore(
                                tmdbID: preview.id,
                                kind: preview.kind,
                                title: preview.title,
                                posterPath: preview.posterPath,
                                context: context
                            )
                            dismiss()
                        } label: {
                            Label("Not interested", systemImage: "hand.thumbsdown")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadAvailability() }
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(Theme.secondary)
                Text("Checking where to watch…")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
        } else if let availability {
            VStack(alignment: .leading, spacing: 6) {
                if !availability.free.isEmpty {
                    line("Free", availability.free, colour: Theme.free)
                }
                if !availability.subscription.isEmpty {
                    line("Subscription", availability.subscription, colour: Theme.secondary)
                }
                if !availability.rentOrBuy.isEmpty {
                    line("Rent or buy", availability.rentOrBuy, colour: Theme.tertiary)
                }
                if availability.free.isEmpty
                    && availability.subscription.isEmpty
                    && availability.rentOrBuy.isEmpty {
                    Text("Nothing listed in \(AppSettings.region).")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    private func line(_ label: String, _ names: [String], colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.tertiary)
            Text(names.joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(colour)
        }
    }

    private func loadAvailability() async {
        isLoading = true
        defer { isLoading = false }
        switch preview.kind {
        case .tv:
            availability = try? await TMDBClient.shared.availability(id: preview.id)
        case .movies:
            availability = try? await TMDBClient.shared.movieAvailability(id: preview.id)
        }
    }
}
