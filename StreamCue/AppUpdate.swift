import SwiftUI

/// Checks the App Store for a newer release than the one running. Results go
/// in UserDefaults so the Shows tab can read them through @AppStorage and the
/// card survives relaunches between checks.
///
/// Only App Store releases count: a TestFlight build is normally ahead of the
/// store, so it never sees a card, and a build that isn't on the store yet
/// (or in this storefront) gets no lookup result at all.
enum AppUpdate {
    static let latestVersionKey = "appStoreLatestVersion"
    static let storeURLKey = "appStoreURL"
    static let dismissedVersionKey = "appStoreDismissedVersion"
    private static let lastCheckedKey = "appStoreLastChecked"

    /// The lookup is cheap, but a release doesn't need spotting to the minute.
    private static let interval: TimeInterval = 6 * 60 * 60

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct Lookup: Decodable {
        let results: [Release]

        struct Release: Decodable {
            let version: String
            let trackViewUrl: URL
            let minimumOsVersion: String?
        }
    }

    static func check() async {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        guard now - defaults.double(forKey: lastCheckedKey) > interval,
              let bundleID = Bundle.main.bundleIdentifier else { return }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let lookup = try? JSONDecoder().decode(Lookup.self, from: data) else { return }

        defaults.set(now, forKey: lastCheckedKey)

        // Not on the store here, or the new release needs a newer iOS than
        // this device has — nothing it could install, so no card.
        guard let release = lookup.results.first,
              isOSSupported(release.minimumOsVersion) else {
            defaults.removeObject(forKey: latestVersionKey)
            return
        }
        defaults.set(release.version, forKey: latestVersionKey)
        defaults.set(release.trackViewUrl.absoluteString, forKey: storeURLKey)
    }

    /// Compares dotted versions number by number, so 2.3.17 beats 2.3.9 and
    /// 2.3 equals 2.3.0.
    static func isNewer(_ version: String, than other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func isOSSupported(_ minimum: String?) -> Bool {
        guard let minimum else { return true }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return !isNewer(minimum, than: current)
    }
}

/// Sits at the top of the Shows tab until you update or dismiss it. Dismissing
/// hides it for that version only — the next release brings it back.
struct UpdateCard: View {
    let version: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.title2)
                .foregroundStyle(Theme.free)

            VStack(alignment: .leading, spacing: 3) {
                Text("Update available")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primary)
                Text("StreamCue \(version) is on the App Store")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                Button("Update", action: onUpdate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.free)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.tertiary)
                }
                .accessibilityLabel("Dismiss")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.free).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
    }
}
