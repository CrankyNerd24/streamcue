import Foundation
import Observation

/// One shared source of the household list for the whole app, so the Shows
/// and Movies tabs (each showing their own kind's slice of it) stay in sync
/// with each other without both independently hitting CloudKit. Injected
/// once at the root via `.environment`.
@Observable
final class SharedListStore {
    private(set) var items: [SharedItem] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func items(for kind: MediaKind) -> [SharedItem] {
        items.filter { $0.kind == kind }
    }

    func contains(tmdbID: Int, kind: MediaKind) -> Bool {
        items.contains { $0.tmdbID == tmdbID && $0.kind == kind }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await SharedListManager.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(tmdbID: Int, kind: MediaKind, title: String, posterPath: String?) async {
        do {
            let item = try await SharedListManager.add(
                tmdbID: tmdbID,
                kind: kind,
                title: title,
                posterPath: posterPath
            )
            items.insert(item, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setWatched(_ item: SharedItem, watched: Bool) async {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].watched = watched
        do {
            try await SharedListManager.setWatched(item, watched: watched)
        } catch {
            items[index].watched = !watched
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ item: SharedItem) async {
        let previous = items
        items.removeAll { $0.id == item.id }
        do {
            try await SharedListManager.remove(item)
        } catch {
            items = previous
            errorMessage = error.localizedDescription
        }
    }

}
