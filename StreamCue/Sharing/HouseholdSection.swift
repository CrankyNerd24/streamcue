import SwiftUI

/// The household's shared list, filtered to one kind — dropped into the
/// Shows tab (`.tv`) and the Movies tab (`.movies`) so each shows its own
/// slice of the same underlying list. Hidden entirely once there's nothing
/// of that kind, same as the other conditional sections on those tabs.
struct HouseholdSection: View {
    let kind: MediaKind

    @Environment(SharedListStore.self) private var sharedList

    var body: some View {
        let items = sharedList.items(for: kind)
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    HouseholdItemRow(item: item)
                }
                .onDelete { offsets in
                    Task { await sharedList.remove(at: offsets, in: kind) }
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
