import SwiftUI
import SwiftData

struct AddShowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tracked: [TrackedShow]

    @State private var query = ""
    @State private var results: [TVSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var preview: TitlePreview?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                ForEach(results) { result in
                    Button {
                        preview = TitlePreview(result, isTracked: isTracked(result.id))
                    } label: {
                        HStack(spacing: 12) {
                            PosterThumbnail(path: result.posterPath)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .font(.headline)
                                if let year = result.year {
                                    Text(year)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isTracked(result.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "Find a show",
                        systemImage: "magnifyingglass",
                        description: Text("Type a title and hit search.")
                    )
                }
            }
            .searchable(text: $query, prompt: "Show title")
            .onSubmit(of: .search) { Task { await search() } }
            .sheet(item: $preview) { preview in
                TitlePreviewSheet(preview: preview) { add(preview) }
            }
            .navigationTitle("Add a show")
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
            results = try await TMDBClient.shared.searchShows(query)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
    }

    /// Called from the preview's Add (and Watched) button. The preview
    /// dismisses itself; the search sheet stays open so you can add another.
    private func add(_ preview: TitlePreview) {
        guard !isTracked(preview.id) else { return }
        let show = Library.addShow(
            tmdbID: preview.id,
            name: preview.title,
            posterPath: preview.posterPath,
            context: context
        )
        Task { try? await show.refresh() }
    }
}
