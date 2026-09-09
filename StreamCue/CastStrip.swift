import SwiftUI

/// Horizontal row of billed cast. Tapping a face opens that person's
/// filmography — the same screen the Look up sheet reaches — so it needs to
/// sit inside a NavigationStack.
struct CastStrip: View {
    let cast: [CastMember]
    var limit: Int = 12

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(cast.prefix(limit)) { member in
                    NavigationLink {
                        CatalogView(title: member.name, source: .person(member.id))
                    } label: {
                        VStack(spacing: 5) {
                            ProfilePhoto(path: member.profilePath, size: 62)
                            Text(member.name)
                                .font(.caption2)
                                .foregroundStyle(Theme.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 68)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
