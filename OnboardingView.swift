import SwiftUI
import SwiftData

/// Shown once, on first launch. Three steps that each do real work, so the app
/// is populated by the end rather than explained.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Subscriptions.key) private var subscriptionsRaw = ""
    @AppStorage(AppSettings.regionKey) private var region = "US"
    @AppStorage(Notifications.enabledKey) private var notificationsEnabled = false
    @AppStorage(Notifications.hourKey) private var notificationHour = 18
    @AppStorage(OnboardingView.completedKey) private var hasCompletedSetup = false

    static let completedKey = "hasCompletedSetup"

    @State private var step = 0

    // Step 1
    @State private var providers: [ProviderInfo] = []
    @State private var chosenServices: Set<Int> = []
    @State private var isLoadingProviders = true

    // Step 2
    @State private var suggestions: [TVSearchResult] = []
    @State private var searchResults: [TVSearchResult] = []
    @State private var query = ""
    @State private var chosenShows: Set<Int> = []
    @State private var isLoadingShows = true

    private var visibleShows: [TVSearchResult] {
        searchResults.isEmpty ? suggestions : searchResults
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress

                Group {
                    switch step {
                    case 0: servicesStep
                    case 1: showsStep
                    default: alertsStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { complete() }
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .task { await loadProviders() }
            .task { await loadSuggestions() }
        }
    }

    // MARK: - Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.tonight : Theme.divider)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") {
                    withAnimation { step -= 1 }
                }
                .foregroundStyle(Theme.secondary)
            }

            Spacer()

            Button(step == 2 ? "Done" : "Continue") {
                if step == 2 {
                    complete()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Theme.tonight, in: Capsule())
        }
        .padding(20)
    }

    private func title(_ text: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Step 1: services

    private var servicesStep: some View {
        VStack(spacing: 0) {
            title("What do you pay for?", "So the app can tell you what's already included.")

            HStack {
                Text("Country")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Picker("Country", selection: $region) {
                    ForEach(WatchRegion.all, id: \.code) { entry in
                        Text(entry.name).tag(entry.code)
                    }
                }
                .labelsHidden()
                .tint(Theme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(providers) { provider in
                        Button {
                            toggle(provider.providerId, in: &chosenServices)
                        } label: {
                            VStack(spacing: 6) {
                                ServiceLogo(path: provider.logoPath, size: 38)
                                Text(provider.providerName)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                chosenServices.contains(provider.providerId)
                                    ? Theme.card : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        chosenServices.contains(provider.providerId)
                                            ? Theme.free : Theme.divider,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .overlay {
                if isLoadingProviders { ProgressView().tint(Theme.secondary) }
            }
        }
    }

    // MARK: - Step 2: shows

    private var showsStep: some View {
        VStack(spacing: 0) {
            title("Add a few shows", "Search for what you watch, or pick from what's popular.")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.tertiary)
                TextField("Show title", text: $query)
                    .foregroundStyle(Theme.primary)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                    spacing: 14
                ) {
                    ForEach(visibleShows) { show in
                        Button {
                            toggle(show.id, in: &chosenShows)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Poster(
                                        path: show.posterPath,
                                        width: 100,
                                        height: 150,
                                        radius: 7
                                    )
                                    if chosenShows.contains(show.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Theme.free)
                                            .padding(5)
                                    }
                                }
                                Text(show.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 100)
                            .opacity(chosenShows.contains(show.id) ? 1 : 0.75)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .overlay {
                if isLoadingShows && visibleShows.isEmpty {
                    ProgressView().tint(Theme.secondary)
                }
            }
        }
    }

    // MARK: - Step 3: alerts

    private var alertsStep: some View {
        VStack(spacing: 0) {
            title("Want a nudge?", "A notification on the day something you track airs.")

            VStack(spacing: 0) {
                Toggle("Air-date alerts", isOn: $notificationsEnabled)
                    .tint(Theme.tonight)
                    .foregroundStyle(Theme.primary)
                    .padding(14)

                if notificationsEnabled {
                    Divider().overlay(Theme.divider)
                    HStack {
                        Text("Alert me at")
                            .foregroundStyle(Theme.primary)
                        Spacer()
                        Picker("Alert me at", selection: $notificationHour) {
                            ForEach(Array(7...22), id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .tint(Theme.secondary)
                    }
                    .padding(14)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            Text("TMDB publishes air dates without times, so alerts fire at the hour you pick rather than at broadcast.")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            Spacer()

            TestCard()
                .padding(.bottom, 30)
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            guard enabled else { return }
            Task {
                if await Notifications.requestPermission() == false {
                    notificationsEnabled = false
                }
            }
        }
    }

    // MARK: - Data

    private func toggle(_ id: Int, in set: inout Set<Int>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    private func loadProviders() async {
        isLoadingProviders = true
        defer { isLoadingProviders = false }
        let all = (try? await TMDBClient.shared.availableProviders()) ?? []
        providers = Array(all.prefix(24))
    }

    private func loadSuggestions() async {
        isLoadingShows = true
        defer { isLoadingShows = false }
        suggestions = (try? await TMDBClient.shared.shows(in: .popular)) ?? []
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchResults = (try? await TMDBClient.shared.searchShows(trimmed)) ?? []
    }

    /// Saves everything picked, then gets out of the way. Shows refresh on
    /// their own when the list appears.
    private func complete() {
        let services = providers
            .filter { chosenServices.contains($0.providerId) }
            .map {
                Subscriptions.Service(
                    id: $0.providerId,
                    name: $0.providerName,
                    logoPath: $0.logoPath
                )
            }
        if !services.isEmpty {
            subscriptionsRaw = Subscriptions.encode(services)
        }

        let picked = (suggestions + searchResults).filter { chosenShows.contains($0.id) }
        var seen = Set<Int>()
        for result in picked where seen.insert(result.id).inserted {
            let show = TrackedShow(
                tmdbID: result.id,
                name: result.name,
                posterPath: result.posterPath
            )
            context.insert(show)
        }

        hasCompletedSetup = true
        dismiss()
    }
}
