import Foundation
import UIKit

/// Resolves "Watch now" to the actual streaming app when possible. TMDB's
/// watch/providers endpoint doesn't expose per-title deep links (only
/// JustWatch's paid affiliate API does), so an app match lands on that
/// app's home screen, not the title itself. When nothing matches, the
/// fallback is the stored JustWatch link — presented in an in-app Safari
/// sheet (see `Presentation.web`, `SafariView`) rather than a full app
/// switch, since it's an intermediate stop, not the real destination.
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

    /// Drives the button's styling — `.free` is the only one that ever gets
    /// `Theme.free`. A service you pay for is still a paid service even when
    /// it happens to be the one you subscribed to.
    enum Kind {
        case subscribed
        case free
        case other
    }

    /// Whether tapping the button hands off to another app, or should stay
    /// in StreamCue via an in-app Safari sheet. The JustWatch fallback is
    /// always `.web` — no reason to fully kick someone out to Safari for a
    /// page that's just an intermediate stop, not the destination itself.
    enum Presentation {
        case app
        case web
    }

    struct Destination {
        let label: String
        let url: URL
        let kind: Kind
        let presentation: Presentation
    }

    /// Picks where "Watch now" should go, in priority order: a service the
    /// user already pays for beats free/ad-supported, which beats anything
    /// else (rent/buy, or a subscription service that isn't theirs). Within
    /// whichever group wins, the first entry with an installed, mapped app
    /// deep-links straight in; otherwise the whole call falls back to the
    /// stored JustWatch link, still carrying that group's `Kind` so the
    /// button styles correctly either way.
    static func destination(
        free: [String],
        subscription: [String],
        rentOrBuy: [String],
        mySubscriptions: Set<String>,
        watchLink: String?
    ) -> Destination? {
        let subscribedHere = subscription.filter { mySubscriptions.contains($0) }
        let otherSubscription = subscription.filter { !mySubscriptions.contains($0) }

        let groups: [(names: [String], kind: Kind)] = [
            (subscribedHere, .subscribed),
            (free, .free),
            (otherSubscription + rentOrBuy, .other)
        ]

        for group in groups {
            for name in group.names {
                if let scheme = schemes[name],
                   let url = URL(string: scheme),
                   UIApplication.shared.canOpenURL(url) {
                    return Destination(label: "Open in \(name)", url: url, kind: group.kind, presentation: .app)
                }
            }
        }

        guard let leadGroup = groups.first(where: { !$0.names.isEmpty }),
              let watchLink, let url = URL(string: watchLink) else {
            return nil
        }
        return Destination(label: "Watch now", url: url, kind: leadGroup.kind, presentation: .web)
    }
}
