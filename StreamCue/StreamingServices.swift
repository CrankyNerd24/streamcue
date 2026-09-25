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

    /// A per-title "Watch on" choice that replaces the automatic pick — for
    /// a service TMDB doesn't list (Dropout shows up as Amazon, for one), or
    /// just a preference. `link` is optional for a service with a mapped app.
    struct Override {
        let name: String
        let link: String?
    }

    /// Picks where "Watch now" should go. An override wins outright. Otherwise, in priority order: a service the
    /// user has ticked on the Services tab (paid, then free), then any other
    /// free/ad-supported one, then anything else (rent/buy, or a
    /// subscription service that isn't theirs). Within whichever group
    /// wins, the first entry with an installed, mapped app deep-links
    /// straight in. If the title is on one of the user's own services, the
    /// search stops there — better their service's JustWatch page than
    /// some other app they don't pay for. Otherwise the whole call falls
    /// back to the stored JustWatch link, still carrying the lead group's
    /// `Kind` so the button styles correctly either way.
    static func destination(
        free: [String],
        subscription: [String],
        rentOrBuy: [String],
        mySubscriptions: Set<String>,
        watchLink: String?,
        override: Override? = nil
    ) -> Destination? {
        if let override {
            if let destination = destination(for: override) {
                return destination
            }
            // Picked one of their services that has no mapped app and no
            // link of its own: the JustWatch page, rather than letting the
            // automatic pick send them somewhere they didn't choose.
            if let watchLink, let url = URL(string: watchLink) {
                return Destination(label: "Watch now", url: url, kind: .subscribed, presentation: .web)
            }
        }

        let subscribedHere = subscription.filter { mySubscriptions.contains($0) }
        let otherSubscription = subscription.filter { !mySubscriptions.contains($0) }
        let myFree = free.filter { mySubscriptions.contains($0) }
        let otherFree = free.filter { !mySubscriptions.contains($0) }

        let mine: [(names: [String], kind: Kind)] = [
            (subscribedHere, .subscribed),
            (myFree, .free)
        ]
        let rest: [(names: [String], kind: Kind)] = [
            (otherFree, .free),
            (otherSubscription + rentOrBuy, .other)
        ]
        let isOnMyServices = mine.contains { !$0.names.isEmpty }
        let groups = isOnMyServices ? mine : mine + rest

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

    /// The mapped app if it's installed, else the override's own link. A
    /// web link still goes out via `openURL` (`.app`) rather than the
    /// in-app sheet: it's the real destination, and a universal link opens
    /// the service's app when there is one.
    private static func destination(for override: Override) -> Destination? {
        if let scheme = schemes[override.name],
           let url = URL(string: scheme),
           UIApplication.shared.canOpenURL(url) {
            return Destination(label: "Open in \(override.name)", url: url, kind: .subscribed, presentation: .app)
        }
        if let link = override.link, let url = URL(string: link) {
            return Destination(label: "Open in \(override.name)", url: url, kind: .subscribed, presentation: .app)
        }
        return nil
    }

    /// Tidies a typed link: adds https:// when there's no scheme, and
    /// rejects anything without a host. Returns nil for unusable input.
    static func normalizedLink(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }
}
