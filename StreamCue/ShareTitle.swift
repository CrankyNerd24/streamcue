import SwiftUI

/// What the Share button sends for a show or film: its title and where it
/// streams, plus a link to its TMDB page, which opens in any browser — the
/// person receiving it doesn't need StreamCue.
struct TitleShare {
    let tmdbID: Int
    let kind: MediaKind
    let title: String
    var free: [String] = []
    var subscription: [String] = []

    var url: URL {
        let path = kind == .tv ? "tv" : "movie"
        return URL(string: "https://www.themoviedb.org/\(path)/\(tmdbID)")!
    }

    /// "Severance — streaming on Apple TV+". Availability is for this
    /// device's region, which is usually the recipient's too.
    var message: String {
        var text = title
        if let service = free.first {
            text += " — free on \(service)"
        } else if !subscription.isEmpty {
            text += " — streaming on \(subscription.prefix(2).joined(separator: ", "))"
        }
        // Filled in by the App Store lookup, so this only appears once
        // StreamCue is actually on the store.
        if let store = UserDefaults.standard.string(forKey: AppUpdate.storeURLKey), !store.isEmpty {
            text += "\n\nTracked with StreamCue: \(store)"
        }
        return text
    }
}

struct ShareTitleButton: View {
    let share: TitleShare

    var body: some View {
        ShareLink(
            item: share.url,
            subject: Text(share.title),
            message: Text(share.message)
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}
