import Foundation
import UIKit

/// Resolves "Watch now" to the actual streaming app when possible, so
/// tapping it doesn't route through a JustWatch page you then have to tap
/// through again. TMDB's watch/providers endpoint doesn't expose per-title
/// deep links (only JustWatch's paid affiliate API does), so this lands on
/// the app's home screen, not the title itself — still one hop closer than
/// today.
enum StreamingServices {
    /// Provider name as TMDB returns it, mapped to that app's URL scheme.
    /// Anything not listed here, or not installed, falls back to the stored
    /// JustWatch link.
    private static let schemes: [String: String] = [
        "Netflix": "nflx://",
        "Amazon Prime Video": "aiv://aiv/home",
        "Disney Plus": "disneyplus://",
        "Hulu": "hulu://",
        "Max": "hbomax://",
        "HBO Max": "hbomax://",
        "Paramount Plus": "paramountplus://",
        "Apple TV Plus": "videos://",
        "Apple TV": "videos://",
        "Peacock": "peacocktv://",
        "Peacock Premium": "peacocktv://",
        "YouTube": "youtube://",
    ]

    struct Destination {
        let label: String
        let url: URL
    }

    /// `providers` should already be in the priority you'd want to watch on
    /// (free before subscription before rent/buy) — the first one with an
    /// installed, mapped app wins.
    static func destination(providers: [String], watchLink: String?) -> Destination? {
        for name in providers {
            if let scheme = schemes[name],
               let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                return Destination(label: "Open in \(name)", url: url)
            }
        }
        if let watchLink, let url = URL(string: watchLink) {
            return Destination(label: "Watch now", url: url)
        }
        return nil
    }
}
