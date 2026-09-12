# StreamCue

iOS app for tracking TV shows and films: what's airing, where it streams, and
whether it's free. SwiftUI + SwiftData, no backend.

## Build

- Xcode 26, **deployment target iOS 18** (`onScrollGeometryChange` needs it)
- `Secrets.swift` is gitignored — see `Secrets.example.swift`. It holds a TMDB
  v4 read token and an optional OMDb key.
- Xcode 26 defaults to main-actor isolation. Anything the API client touches
  off the main actor must be explicitly `nonisolated` (see `Settings.swift`,
  `Secrets.swift`). This is the most common build failure in this project.

## Architecture

| File | Role |
|---|---|
| `StreamCueApp.swift` | Entry point, tab bar, SwiftData container, background task |
| `ContentView.swift` | Shows tab — sections, filtering, Settings sheet |
| `WatchlistView.swift` | Movies tab — grouping, search, detail, suggestions |
| `SubscriptionsView.swift` | Services tab — picker, per-service recommendations |
| `DiscoverView.swift` | Discover tab — TV/film × for-you/trending/popular |
| `LookupView.swift` | Search by title, person, or studio; `CatalogView` grid |
| `TitlePreview.swift` | Preview sheet shown before anything is added |
| `Library.swift` | **All inserts go through here** — dedup, ignore |
| `TMDB.swift` | TMDB client and every response model |

## Rules that matter

**Never read `nextAirDate` outside `TrackedShow.swift`.** Use
`effectiveAirDate`, which applies the per-show `dayOffset`. Grouping, labels,
notifications and reminders all depend on agreeing with each other.

**Never call `context.insert` for a tracked show or film.** Use
`Library.addShow` / `Library.addMovie`, which dedupe. The models deliberately
have no `@Attribute(.unique)` because CloudKit can't enforce it.

**Every stored property needs a default value.** Same reason.

**Adding or changing a `@Model` field is a schema change.** The app will crash
on launch against an existing store — delete and reinstall.

**Colour means something.** Orange (`Theme.tonight`) is only ever "airing
today". Green (`Theme.free`) is only ever "free to watch". Amber
(`Theme.unwatched`) is only ever "aired, not actioned". The test-pattern
colour-bar spine appears only on a show airing today.

**Tapping a poster never adds anything.** It opens `TitlePreviewSheet`, which
has the Add and Not interested buttons.

## API notes

- TMDB publishes an air **date** with no time and no timezone. Parse it in the
  local calendar at midday (`TMDBDate.parse`) — parsing as UTC lands it on the
  previous evening in the US.
- Don't use `.convertFromSnakeCase` on the decoder: it lowercases the country
  keys in the watch-providers response. Every model uses explicit `CodingKeys`.
- OMDb's free tier is 1,000/day and its TV coverage is thin. Ratings are
  skipped on automatic refreshes unless a title has none.
- TMDB genre IDs differ between TV and film. Don't mix them.

## Known gaps

- CloudKit sync is written (`StreamCueApp.swift`) but needs a paid developer
  account, which isn't available yet.
- OMDb attribution is required by its CC BY-NC licence and isn't displayed.
- The Help screen says data never leaves the device. That stops being true if
  CloudKit is enabled.
