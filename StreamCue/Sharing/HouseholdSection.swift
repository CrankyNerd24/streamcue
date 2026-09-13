import SwiftUI

/// The household's shared list, filtered to one kind — dropped into the
/// Shows tab (`.tv`) and the Movies tab (`.movies`) so each shows its own
/// slice of the same underlying list. Hidden entirely once there's nothing
/// left to show, same as the other conditional sections on those tabs.
///
/// `personalTmdbIDs` hides anything already on this device's own personal
/// list — the shared item is still an independent copy underneath, but
/// there's no reason to show someone the same title twice just because they
/// were the one who added it. A household member who doesn't personally
/// track it still sees it in their own Household section.
struct HouseholdSection: View {
    let kind: MediaKind
    let personalTmdbIDs: Set<Int>

    @Environment(SharedListStore.self) private var sharedList

    var body: some View {
        let items = sharedList.items(for: kind).filter { !personalTmdbIDs.contains($0.tmdbID) }
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    HouseholdItemRow(item: item)
                }
                .onDelete { offsets in
                    let toRemove = offsets.map { items[$0] }
                    Task {
                        for item in toRemove { await sharedList.remove(item) }
                    }
                }
            } header: {
                Text("Household")
                    .font(.caption)
                    .kerning(0.5)
                    .foregroundStyle(Theme.secondary)
            } footer: {
                Text("Shared with everyone on the household list. Tap to mark watched.")
            }
        }
    }
}

private struct HouseholdItemRow: View {
    let item: SharedItem

    @Environment(SharedListStore.self) private var sharedList

    var body: some View {
        Button {
            Task { await sharedList.setWatched(item, watched: !item.watched) }
        } label: {
            HStack(spacing: 10) {
                Poster(path: item.posterPath, width: 34, height: 51, radius: 4)
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(item.watched ? Theme.secondary : Theme.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.watched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.free)
                }
            }
            .opacity(item.watched ? 0.6 : 1)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .plainRow()
    }
}
