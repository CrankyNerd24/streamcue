import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Bindable var show: TrackedShow

    @State private var isRefreshing = false
    @State private var isWorkingOnReminder = false
    @State private var isAddingToHousehold = false
    @State private var cast: [CastMember] = []
    @State private var errorMessage: String?
    @State private var isShowingPaywall = false
    @State private var isShowingWatchNowSheet = false
    @Environment(\.openURL) private var openURL
    @AppStorage(Subscriptions.key) private var subscriptionsRaw = ""

    private var mySubscriptions: Set<String> {
        Set(Subscriptions.decode(subscriptionsRaw).map(\.name))
    }

    private var watchNowDestination: StreamingServices.Destination? {
        StreamingServices.destination(
            free: show.freeOn,
            subscription: show.subscriptionOn,
            rentOrBuy: show.rentOrBuyOn,
            mySubscriptions: mySubscriptions,
            watchLink: show.watchLink
        )
    }

    @Environment(SharedListStore.self) private var sharedList
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    CachedImage(url: TMDBImage.poster(show.posterPath)) {
                        Rectangle().fill(Theme.posterWell)
                    }
                    .frame(width: 90, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(show.name).font(.title3.bold())
                        Text(show.status.isEmpty ? "—" : show.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !show.overview.isEmpty {
                Section {
                    Text(show.overview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }

            if show.hasAnyRating {
                Section("Ratings") {
                    HStack(spacing: 22) {
                        if let imdb = show.imdbScore {
                            ScoreBadge(label: "IMDb", value: imdb)
                        }
                        if let tomatoes = show.rottenTomatoesScore {
                            ScoreBadge(label: "Rotten Tomatoes", value: tomatoes)
                        }
                        if let metacritic = show.metacriticScore {
                            ScoreBadge(label: "Metacritic", value: metacritic)
                        }
                        if let tmdb = show.tmdbScore, tmdb > 0 {
                            ScoreBadge(label: "TMDB", value: String(format: "%.1f", tmdb))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                LabeledContent("Next") {
                    Text(show.effectiveAirDate == nil ? "No date announced" : show.scheduleSummary)
                        .multilineTextAlignment(.trailing)
                }
                if let synopsis = show.nextEpisodeOverview, !synopsis.isEmpty {
                    DisclosureGroup("Episode synopsis") {
                        Text(synopsis)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Stepper(value: $show.dayOffset, in: -7...14) {
                    HStack {
                        Text("Day offset")
                        Spacer()
                        Text(offsetLabel)
                            .foregroundStyle(show.dayOffset == 0 ? Theme.tertiary : Theme.tonight)
                            .monospacedDigit()
                    }
                }

                if let last = show.lastEpisodeLabel {
                    LabeledContent("Last aired") {
                        Text(last).multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Air dates are the original broadcaster's. Use the offset if this reaches you on a different day.")
            }

            if !cast.isEmpty {
                Section("Cast") {
                    CastStrip(cast: cast)
                }
            }

            if let watchNowDestination {
                Section {
                    if purchases.isPremium {
                        Button {
                            switch watchNowDestination.presentation {
                            case .app:
                                openURL(watchNowDestination.url)
                            case .web:
                                isShowingWatchNowSheet = true
                            }
                        } label: {
                            Label(watchNowDestination.label, systemImage: "play.rectangle.fill")
                        }
                        .tint(watchNowDestination.kind == .free ? Theme.free : nil)
                    } else {
                        Button {
                            isShowingPaywall = true
                        } label: {
                            HStack {
                                Label(watchNowDestination.label, systemImage: "play.rectangle.fill")
                                    .foregroundStyle(Theme.primary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                } footer: {
                    if !purchases.isPremium {
                        Text("Part of StreamCue Premium.")
                    }
                }
            }

            if !show.freeOn.isEmpty {
                Section("Free") {
                    ForEach(show.freeOn, id: \.self, content: Text.init)
                }
            }
            if !show.subscriptionOn.isEmpty {
                Section("With a subscription") {
                    ForEach(show.subscriptionOn, id: \.self, content: Text.init)
                }
            }
            if !show.rentOrBuyOn.isEmpty {
                Section("Rent or buy") {
                    ForEach(show.rentOrBuyOn, id: \.self, content: Text.init)
                }
            }
            if show.freeOn.isEmpty && show.subscriptionOn.isEmpty && show.rentOrBuyOn.isEmpty {
                Section("Where to watch") {
                    Text("Nothing listed in \(AppSettings.region).")
                        .foregroundStyle(.secondary)
                }
            }

            if show.effectiveAirDate != nil {
                Section {
                    Button {
                        Task { await toggleReminder() }
                    } label: {
                        HStack {
                            Label(
                                show.reminderID == nil ? "Add to Reminders" : "Remove from Reminders",
                                systemImage: show.reminderID == nil ? "bell.badge" : "bell.slash"
                            )
                            Spacer()
                            if isWorkingOnReminder { ProgressView() }
                        }
                    }
                    .disabled(isWorkingOnReminder)
                }
            }

            Section {
                Button(role: isOnHouseholdList ? .destructive : nil) {
                    Task { await toggleHousehold() }
                } label: {
                    HStack {
                        Label(
                            isOnHouseholdList ? "Remove from household list" : "Add to household list",
                            systemImage: isOnHouseholdList ? "person.2.slash" : "person.2"
                        )
                        Spacer()
                        if isAddingToHousehold { ProgressView() }
                    }
                }
                .disabled(isAddingToHousehold)
            } footer: {
                Text("An independent copy on the shared household list — removing it later from either list won't affect the other.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                EmptyView()
            } footer: {
                if let lastRefreshed = show.lastRefreshed {
                    Text("Updated \(lastRefreshed.formatted(.relative(presentation: .named)))")
                }
            }
        }
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                Task { await refresh() }
            } label: {
                if isRefreshing {
                    ProgressView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
        }
        .task {
            if show.lastRefreshed == nil { await refresh() }
        }
        .task {
            cast = (try? await TMDBClient.shared.cast(
                forID: show.tmdbID,
                kind: .tv
            )) ?? []
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $isShowingWatchNowSheet) {
            if let watchNowDestination {
                SafariView(url: watchNowDestination.url)
            }
        }
    }

    private var offsetLabel: String {
        switch show.dayOffset {
        case 0: return "None"
        case 1: return "+1 day"
        case -1: return "−1 day"
        case let value where value > 0: return "+\(value) days"
        case let value: return "−\(abs(value)) days"
        }
    }

    private func toggleReminder() async {
        isWorkingOnReminder = true
        errorMessage = nil
        defer { isWorkingOnReminder = false }

        if let existing = show.reminderID {
            await RemindersService.shared.remove(identifier: existing)
            show.reminderID = nil
            return
        }

        guard let airDate = show.effectiveAirDate else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: airDate)
        components.hour = Notifications.hour
        components.minute = 0
        guard let due = Calendar.current.date(from: components) else { return }

        do {
            show.reminderID = try await RemindersService.shared.add(
                title: "Watch \(show.name)",
                notes: show.nextEpisodeLabel,
                due: due
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        do {
            try await show.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    private var isOnHouseholdList: Bool {
        sharedList.contains(tmdbID: show.tmdbID, kind: .tv)
    }

    private func toggleHousehold() async {
        if let existing = sharedList.item(tmdbID: show.tmdbID, kind: .tv) {
            isAddingToHousehold = true
            defer { isAddingToHousehold = false }
            await sharedList.remove(existing)
        } else {
            guard purchases.isPremium else {
                isShowingPaywall = true
                return
            }
            isAddingToHousehold = true
            defer { isAddingToHousehold = false }
            await sharedList.add(
                tmdbID: show.tmdbID,
                kind: .tv,
                title: show.name,
                posterPath: show.posterPath
            )
        }
    }
}

struct ScoreBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
