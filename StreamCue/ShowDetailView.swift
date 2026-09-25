import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Bindable var show: TrackedShow

    @State private var isRefreshing = false
    @State private var isWorkingOnReminder = false
    @State private var isAddingToHousehold = false
    @State private var cast: [CastMember] = []
    @State private var errorMessage: String?
    @State private var isShowingWatchNowSheet = false
    @State private var isEditingCustomWatchOn = false
    @State private var draftWatchOnName = ""
    @State private var draftWatchOnLink = ""
    @Environment(\.openURL) private var openURL
    @AppStorage(Subscriptions.key) private var subscriptionsRaw = ""

    private var mySubscriptions: Set<String> {
        Set(Subscriptions.decode(subscriptionsRaw).map(\.name))
    }

    private var watchNowDestination: StreamingServices.Destination? {
        show.watchNowDestination(mySubscriptions: mySubscriptions)
    }

    private static let customWatchOnTag = "\u{1}custom"

    /// The subscribed services, alphabetical, for the Watch on menu.
    private var subscribedNames: [String] {
        mySubscriptions.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A picked subscribed service is stored as just its name; anything with
    /// its own link (or a name that's no longer subscribed) is "custom".
    private var isCustomWatchOn: Bool {
        guard let name = show.watchOnName else { return false }
        return show.watchOnLink != nil || !mySubscriptions.contains(name)
    }

    private var watchOnSelection: Binding<String> {
        Binding(
            get: {
                guard let name = show.watchOnName else { return "" }
                return isCustomWatchOn ? Self.customWatchOnTag : name
            },
            set: { tag in
                switch tag {
                case "":
                    show.watchOnName = nil
                    show.watchOnLink = nil
                case Self.customWatchOnTag:
                    break
                default:
                    show.watchOnName = tag
                    show.watchOnLink = nil
                }
            }
        )
    }

    @Environment(SharedListStore.self) private var sharedList

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
                .onChange(of: show.dayOffset) { _, dayOffset in
                    Task { await sharedList.syncDayOffset(tmdbID: show.tmdbID, dayOffset: dayOffset) }
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

            Section {
                if let watchNowDestination {
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
                }

                Picker("Watch on", selection: watchOnSelection) {
                    Text("Automatic").tag("")
                    ForEach(subscribedNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if isCustomWatchOn, let name = show.watchOnName {
                        Text(name).tag(Self.customWatchOnTag)
                    }
                }
                .pickerStyle(.menu)

                Button(isCustomWatchOn ? "Edit custom link…" : "Custom link…") {
                    draftWatchOnName = isCustomWatchOn ? (show.watchOnName ?? "") : ""
                    draftWatchOnLink = show.watchOnLink ?? ""
                    isEditingCustomWatchOn = true
                }
            } footer: {
                Text("Automatic picks a service you've ticked on the Services tab first. Use a custom link for a service TMDB doesn't list.")
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
        .sheet(isPresented: $isShowingWatchNowSheet) {
            if let watchNowDestination {
                SafariView(url: watchNowDestination.url)
            }
        }
        .alert("Custom link", isPresented: $isEditingCustomWatchOn) {
            TextField("Name, e.g. Dropout", text: $draftWatchOnName)
            TextField("Link, e.g. dropout.tv", text: $draftWatchOnLink)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save", action: saveCustomWatchOn)
            if isCustomWatchOn {
                Button("Remove", role: .destructive) {
                    show.watchOnName = nil
                    show.watchOnLink = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Watch now opens this instead — the service's app if it's installed, otherwise its website.")
        }
    }

    /// Refuses a link that doesn't parse rather than saving something Watch
    /// now can't open. A blank name falls back to the link's host.
    private func saveCustomWatchOn() {
        guard let url = StreamingServices.normalizedLink(draftWatchOnLink) else {
            errorMessage = "That link doesn't look right — try something like dropout.tv."
            return
        }
        errorMessage = nil
        let typedName = draftWatchOnName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        show.watchOnName = typedName.isEmpty ? host : typedName
        show.watchOnLink = url.absoluteString
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
        isAddingToHousehold = true
        defer { isAddingToHousehold = false }
        if let existing = sharedList.item(tmdbID: show.tmdbID, kind: .tv) {
            await sharedList.remove(existing)
        } else {
            await sharedList.add(
                tmdbID: show.tmdbID,
                kind: .tv,
                title: show.name,
                posterPath: show.posterPath,
                dayOffset: show.dayOffset
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
