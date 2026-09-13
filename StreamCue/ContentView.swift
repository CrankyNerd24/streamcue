import SwiftUI
import SwiftData
import CloudKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedShow.name) private var shows: [TrackedShow]
    @Query(
        filter: #Predicate<PendingEpisode> { !$0.watched && !$0.dismissed },
        sort: \PendingEpisode.airDate,
        order: .reverse
    ) private var pending: [PendingEpisode]

    @State private var isAdding = false
    @State private var isShowingAbout = false
    @State private var isShowingHelp = false
    @State private var isShowingFilter = false
    @State private var isRefreshing = false
    @State private var isConfirmingReminders = false
    @State private var isWorkingOnReminders = false
    @State private var reminderResult: String?
    @State private var isConfirmingAddAllToHousehold = false
    @State private var isAddingAllToHousehold = false

    @Environment(SharedListStore.self) private var sharedList

    @AppStorage("serviceFilter") private var serviceFilterRaw = ""
    @AppStorage("freeOnly") private var freeOnly = false
    @AppStorage("lastAutoRefresh") private var lastAutoRefresh: Double = 0
    @AppStorage("readyExpanded") private var isReadyExpanded = true

    @Environment(\.scenePhase) private var scenePhase

    private var selectedServices: Set<String> {
        Set(serviceFilterRaw.split(separator: "\n").map(String.init))
    }

    private var isFiltering: Bool { !selectedServices.isEmpty || freeOnly }

    private var knownServices: [String] {
        Set(shows.flatMap { $0.freeOn + $0.subscriptionOn }).sorted()
    }

    // MARK: - Filtering and grouping

    private var visible: [TrackedShow] {
        shows.filter { show in
            if freeOnly && show.freeOn.isEmpty { return false }
            guard !selectedServices.isEmpty else { return true }
            let on = Set(show.freeOn + show.subscriptionOn)
            return !on.isDisjoint(with: selectedServices)
        }
    }

    /// Everything with a known date, soonest first.
    private var dated: [TrackedShow] {
        visible.filter { $0.effectiveAirDate != nil }
            .sorted { ($0.effectiveAirDate ?? .distantFuture) < ($1.effectiveAirDate ?? .distantFuture) }
    }

    /// On today. Gets the card treatment and the colour-bar spine.
    private var airingToday: [TrackedShow] {
        dated.filter { show in
            guard let date = show.effectiveAirDate else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var upcoming: [TrackedShow] {
        let promoted = Set(airingToday.map(\.tmdbID))
        return dated.filter { !promoted.contains($0.tmdbID) }
    }

    private var finished: [TrackedShow] {
        visible.filter { $0.effectiveAirDate == nil && Self.endedStatuses.contains($0.status) }
    }

    private var waiting: [TrackedShow] {
        visible.filter { $0.effectiveAirDate == nil && !Self.endedStatuses.contains($0.status) }
    }

    private static let endedStatuses: Set<String> = ["Ended", "Canceled", "Cancelled"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if shows.isEmpty {
                    empty(
                        "No shows yet",
                        message: "Tap + to find a show and start tracking it."
                    )
                } else if visible.isEmpty {
                    empty(
                        "Nothing matches",
                        message: "No tracked shows are on the services you picked.",
                        action: ("Clear filter", clearFilter)
                    )
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Shows")
            .toolbar { toolbar }
            .confirmationDialog(
                "Add \(remindable.count) reminder\(remindable.count == 1 ? "" : "s")?",
                isPresented: $isConfirmingReminders,
                titleVisibility: .visible
            ) {
                Button("Add to Reminders") {
                    Task { await addAllReminders() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One per show with a confirmed air date, due at \(Notifications.hour):00 on the day it airs.")
            }
            .confirmationDialog(
                "Add \(addableToHousehold.count) show\(addableToHousehold.count == 1 ? "" : "s") to the household list?",
                isPresented: $isConfirmingAddAllToHousehold,
                titleVisibility: .visible
            ) {
                Button("Add to household list") {
                    Task { await addAllToHousehold() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each becomes an independent copy — removing it later from either list won't affect the other.")
            }
            .alert(
                "Reminders",
                isPresented: Binding(
                    get: { reminderResult != nil },
                    set: { if !$0 { reminderResult = nil } }
                )
            ) {
                Button("OK", role: .cancel) { reminderResult = nil }
            } message: {
                Text(reminderResult ?? "")
            }
            .task {
                await Notifications.syncEnabledState()
                await autoRefresh()
            }
            .task(id: pending.count) { await Notifications.updateBadge(pending.count) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task {
                        await Notifications.syncEnabledState()
                        await autoRefresh()
                    }
                case .background:
                    BackgroundRefresh.schedule()
                default:
                    break
                }
            }
            .sheet(isPresented: $isAdding) { AddShowView() }
            .sheet(isPresented: $isShowingHelp) {
                NavigationStack {
                    HelpView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingHelp = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView { Task { await refreshAll() } }
            }
            .sheet(isPresented: $isShowingFilter) {
                ServiceFilterView(
                    services: knownServices,
                    selected: selectedServices,
                    freeOnly: freeOnly
                ) { services, free in
                    serviceFilterRaw = services.sorted().joined(separator: "\n")
                    freeOnly = free
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Refresh all", systemImage: "arrow.clockwise")
                }
                .disabled(shows.isEmpty || isRefreshing)

                Button {
                    isConfirmingReminders = true
                } label: {
                    Label("Add all to Reminders", systemImage: "bell.badge")
                }
                .disabled(remindable.isEmpty || isWorkingOnReminders)

                if !reminded.isEmpty {
                    Button(role: .destructive) {
                        Task { await removeAllReminders() }
                    } label: {
                        Label("Remove all reminders", systemImage: "bell.slash")
                    }
                    .disabled(isWorkingOnReminders)
                }

                Button {
                    isConfirmingAddAllToHousehold = true
                } label: {
                    Label("Add all to household list", systemImage: "person.2")
                }
                .disabled(addableToHousehold.isEmpty || isAddingAllToHousehold)

                Divider()

                Button {
                    isShowingAbout = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button {
                    isShowingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
            } label: {
                Label("Menu", systemImage: "ellipsis.circle")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                isShowingFilter = true
            } label: {
                Label(
                    "Filter",
                    systemImage: isFiltering
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .disabled(shows.isEmpty)

            Button {
                isAdding = true
            } label: {
                Label("Add show", systemImage: "plus")
            }
        }
    }

    private var list: some View {
        List {
            if isFiltering {
                filterStrip
            }

            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.secondary)
                    Text("Refreshing…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                .plainRow()
            }

            if !airingToday.isEmpty {
                header("Airing today", accented: true)
                ForEach(airingToday) { show in
                    heroRow(show)
                }
                .onDelete { remove(airingToday, at: $0) }
            }

            readySection

            section("Airing next", upcoming)
            section("No date announced", waiting)
            section("Finished", finished)

            HouseholdSection(kind: .tv, personalTmdbIDs: Set(shows.map(\.tmdbID)))

            Color.clear.frame(height: 12).plainRow()
        }
        .themedList()
        .refreshable { await refreshAll() }
    }

    private var filterStrip: some View {
        HStack {
            Text(filterSummary)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Button("Clear") { clearFilter() }
                .font(.footnote)
                .foregroundStyle(Theme.primary)
        }
        .plainRow()
    }

    private var filterSummary: String {
        var parts: [String] = []
        if freeOnly { parts.append("Free only") }
        let services = selectedServices.sorted()
        if !services.isEmpty {
            parts.append(services.count <= 2
                ? services.joined(separator: ", ")
                : "\(services.count) services")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Pieces

    private func header(
        _ title: String,
        accented: Bool = false,
        color: Color = Theme.tonight
    ) -> some View {
        HStack(spacing: 6) {
            if accented {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.caption)
                .kerning(0.5)
                .foregroundStyle(accented ? color : Theme.secondary)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .plainRow()
    }

    private func heroRow(_ show: TrackedShow) -> some View {
        NavigationLink(destination: ShowDetailView(show: show)) {
            TonightCard(show: show)
        }
        .buttonStyle(.plain)
        .plainRow()
    }

    /// Collapsible, and expanded by default — these are actionable, unlike the
    /// watched list on the Movies tab which is an archive.
    @ViewBuilder
    private var readySection: some View {
        if !pending.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isReadyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.unwatched)
                        .rotationEffect(.degrees(isReadyExpanded ? 90 : 0))
                    Text("Ready to watch")
                        .font(.caption)
                        .kerning(0.5)
                        .foregroundStyle(Theme.unwatched)
                    Text("\(pending.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .plainRow()

            if isReadyExpanded {
                ForEach(pending) { episode in
                    PendingEpisodeCard(
                        episode: episode,
                        onWatched: { episode.watched = true },
                        onDismiss: { episode.dismissed = true }
                    )
                    .plainRow()
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ group: [TrackedShow]) -> some View {
        if !group.isEmpty {
            header(title)
            ForEach(Array(group.enumerated()), id: \.element.id) { index, show in
                NavigationLink(destination: ShowDetailView(show: show)) {
                    CompactRow(show: show, showsDivider: index < group.count - 1)
                }
                .buttonStyle(.plain)
                .plainRow()
            }
            .onDelete { remove(group, at: $0) }
        }
    }

    private func empty(
        _ title: String,
        message: String,
        action: (String, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            TestCard()
                .padding(.bottom, 8)
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .font(.subheadline)
                    .foregroundStyle(Theme.tonight)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Shows that could take a reminder: dated, and not already carrying one.
    private var remindable: [TrackedShow] {
        shows.filter { $0.effectiveAirDate != nil && $0.reminderID == nil }
    }

    private var reminded: [TrackedShow] {
        shows.filter { $0.reminderID != nil }
    }

    private func addAllReminders() async {
        isWorkingOnReminders = true
        defer { isWorkingOnReminders = false }

        let calendar = Calendar.current
        var added = 0
        var skipped = 0

        for show in remindable {
            guard let airDate = show.effectiveAirDate else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: airDate)
            components.hour = Notifications.hour
            components.minute = 0

            guard let due = calendar.date(from: components), due > .now else {
                skipped += 1
                continue
            }

            do {
                show.reminderID = try await RemindersService.shared.add(
                    title: "Watch \(show.name)",
                    notes: show.nextEpisodeLabel,
                    due: due
                )
                added += 1
            } catch {
                // Access denied or no list — no point trying the rest.
                reminderResult = error.localizedDescription
                return
            }
        }

        if added == 0 {
            reminderResult = "Nothing to add."
        } else {
            var message = "Added \(added) reminder\(added == 1 ? "" : "s")."
            if skipped > 0 {
                message += " Skipped \(skipped) already past."
            }
            reminderResult = message
        }
    }

    private func removeAllReminders() async {
        isWorkingOnReminders = true
        defer { isWorkingOnReminders = false }

        var removed = 0
        for show in reminded {
            guard let identifier = show.reminderID else { continue }
            await RemindersService.shared.remove(identifier: identifier)
            show.reminderID = nil
            removed += 1
        }
        reminderResult = "Removed \(removed) reminder\(removed == 1 ? "" : "s")."
    }

    private func clearFilter() {
        serviceFilterRaw = ""
        freeOnly = false
    }

    /// Shows not already on the household list.
    private var addableToHousehold: [TrackedShow] {
        let shared = Set(sharedList.items(for: .tv).map(\.tmdbID))
        return shows.filter { !shared.contains($0.tmdbID) }
    }

    private func addAllToHousehold() async {
        isAddingAllToHousehold = true
        defer { isAddingAllToHousehold = false }
        for show in addableToHousehold {
            await sharedList.add(tmdbID: show.tmdbID, kind: .tv, title: show.name, posterPath: show.posterPath)
        }
    }

    private func remove(_ group: [TrackedShow], at offsets: IndexSet) {
        for index in offsets {
            EpisodeSync.removeAll(forShowID: group[index].tmdbID, context: context)
            context.delete(group[index])
        }
    }

    private func refreshAll() async {
        isRefreshing = true
        for show in shows {
            try? await show.refresh()
            await EpisodeSync.sync(show, context: context)
        }
        EpisodeSync.prune(context: context)
        Library.deduplicate(context: context)
        isRefreshing = false
        await Notifications.reschedule(for: shows)
        await ReminderSync.sync(shows)
    }

    /// Runs when the app opens or returns to the foreground. Skips entirely if
    /// it ran recently, then updates only the shows that have gone stale.
    private func autoRefresh() async {
        let now = Date().timeIntervalSince1970
        guard now - lastAutoRefresh > 60 * 30 else { return }

        let stale = shows.filter(\.isStale)
        guard !stale.isEmpty else {
            lastAutoRefresh = now
            return
        }

        lastAutoRefresh = now
        isRefreshing = true
        for show in stale {
            try? await show.refresh(includeRatings: false)
            await EpisodeSync.sync(show, context: context)
        }
        EpisodeSync.prune(context: context)
        Library.deduplicate(context: context)
        isRefreshing = false
        await Notifications.reschedule(for: shows)
        await ReminderSync.sync(shows)
    }
}

// MARK: - Rows

struct TonightCard: View {
    let show: TrackedShow

    @Environment(SharedListStore.self) private var sharedList

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Poster(path: show.posterPath, width: 62, height: 93, radius: 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(show.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(2)
                    if sharedList.contains(tmdbID: show.tmdbID, kind: .tv) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                Text(show.heroSchedule)
                    .font(.subheadline)
                    .foregroundStyle(Theme.tonight)
                    .lineLimit(1)

                if show.isFreeSomewhere {
                    Text("Free on \(show.freeOn.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(Theme.free)
                        .lineLimit(1)
                } else if !show.subscriptionOn.isEmpty {
                    Text(show.subscriptionOn.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                if let ratings = show.ratingLine {
                    Text(ratings)
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.leading, 6)
        .background(Theme.card)
        .overlay(alignment: .leading) {
            ColorBarSpine().frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A thin strip of test-pattern colour down the edge of the hero card.
struct ColorBarSpine: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Theme.bars.indices, id: \.self) { index in
                Rectangle().fill(Theme.bars[index])
            }
        }
    }
}

/// A small SMPTE-style test card, used where the app has nothing to show.
struct TestCard: View {
    private var reversed: [Color] { Theme.bars.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Theme.bars.indices, id: \.self) { index in
                    Rectangle().fill(Theme.bars[index])
                }
            }
            .frame(height: 84)

            HStack(spacing: 0) {
                ForEach(reversed.indices, id: \.self) { index in
                    Rectangle().fill(reversed[index].opacity(0.45))
                }
            }
            .frame(height: 14)

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { step in
                    Rectangle()
                        .fill(Theme.posterWell.opacity(0.35 + Double(step) * 0.14))
                }
            }
            .frame(height: 20)
        }
        .frame(width: 168)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(0.85)
    }
}

struct CompactRow: View {
    let show: TrackedShow
    var showsDivider: Bool = true

    @Environment(SharedListStore.self) private var sharedList

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Poster(path: show.posterPath, width: 34, height: 51, radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(show.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    Text(show.scheduleSummary)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if sharedList.contains(tmdbID: show.tmdbID, kind: .tv) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiary)
                }

                if let value = show.primaryScore {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(value.0)
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primary)
                        Text(value.1)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .padding(.vertical, 8)

            if showsDivider {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 0.5)
            }
        }
    }
}

struct Poster: View {
    let path: String?
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        CachedImage(url: TMDBImage.poster(path, width: 154)) {
            Rectangle().fill(Theme.posterWell)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Older name kept so other screens keep compiling.
struct PosterThumbnail: View {
    let path: String?
    var body: some View { Poster(path: path, width: 46, height: 69, radius: 4) }
}

// MARK: - Small helpers

extension View {
    /// A list row with no system chrome — background, insets and separator removed.
    func plainRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

extension TrackedShow {
    /// ("8.1", "IMDb") — whichever score we have, with its source.
    var primaryScore: (String, String)? {
        if let imdbScore { return (imdbScore, "IMDb") }
        if let tmdbScore, tmdbScore > 0 {
            return (String(format: "%.1f", tmdbScore), "TMDB")
        }
        return nil
    }

    /// "S02E04 · Tonight" today, "S02E04 · Thu 11 Sep" otherwise.
    var heroSchedule: String {
        guard let date = effectiveAirDate else { return scheduleSummary }
        let when = Calendar.current.isDateInToday(date)
            ? "Tonight"
            : date.formatted(.dateTime.weekday(.abbreviated).month().day())
        return [nextEpisodeLabel, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// "IMDb 8.1 · 91%" for the roomier hero card.
    var ratingLine: String? {
        var parts: [String] = []
        if let imdbScore {
            parts.append("IMDb \(imdbScore)")
        } else if let tmdbScore, tmdbScore > 0 {
            parts.append("TMDB \(String(format: "%.1f", tmdbScore))")
        }
        if let rottenTomatoesScore { parts.append(rottenTomatoesScore) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Filter sheet

struct ServiceFilterView: View {
    let services: [String]
    let onApply: (Set<String>, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working: Set<String>
    @State private var freeOnly: Bool

    init(
        services: [String],
        selected: Set<String>,
        freeOnly: Bool,
        onApply: @escaping (Set<String>, Bool) -> Void
    ) {
        self.services = services
        self.onApply = onApply
        _working = State(initialValue: selected)
        _freeOnly = State(initialValue: freeOnly)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Free to watch only", isOn: $freeOnly)
                        .tint(Theme.free)
                } footer: {
                    Text("Includes ad-supported services.")
                }

                if services.isEmpty {
                    Section {
                        Text("No services found yet. Refresh your shows to load where they stream.")
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    Section("Services") {
                        ForEach(services, id: \.self) { service in
                            Button {
                                toggle(service)
                            } label: {
                                HStack {
                                    Text(service)
                                        .foregroundStyle(Theme.primary)
                                    Spacer()
                                    if working.contains(service) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.free)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        working = []
                        freeOnly = false
                    }
                    .disabled(working.isEmpty && !freeOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(working, freeOnly)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ service: String) {
        if working.contains(service) {
            working.remove(service)
        } else {
            working.insert(service)
        }
    }
}

// MARK: - About

struct AboutView: View {
    /// Called when the region changes, so tracked shows can be re-fetched —
    /// provider data is per-country and goes stale the moment this moves.
    var onRegionChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.regionKey) private var region = "US"
    @AppStorage(Notifications.enabledKey) private var notificationsEnabled = false
    @AppStorage(Notifications.hourKey) private var notificationHour = 18
    @AppStorage(Notifications.privateKey) private var privateNotifications = false
    @AppStorage(ReminderSync.autoKey) private var autoReminders = false

    @Query private var shows: [TrackedShow]
    @Query(sort: \IgnoredTitle.addedAt, order: .reverse) private var ignored: [IgnoredTitle]
    @Environment(\.modelContext) private var context
    @State private var original = AppSettings.region
    @State private var isShowingIgnored = false

    // Temporary, for verifying the household-share CloudKit plumbing before
    // any shared-list UI exists. Remove once that UI lands.
    @State private var householdShare: CKShare?
    @State private var isShowingHouseholdShare = false
    @State private var householdShareError: String?
    @State private var isLoadingHouseholdShare = false

    private func label(for hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    private func presentHouseholdShare() async {
        isLoadingHouseholdShare = true
        defer { isLoadingHouseholdShare = false }
        do {
            householdShare = try await HouseholdShareManager.fetchOrCreateShare()
            isShowingHouseholdShare = true
        } catch {
            householdShareError = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Country", selection: $region) {
                        ForEach(WatchRegion.all, id: \.code) { entry in
                            Text(entry.name).tag(entry.code)
                        }
                    }
                } header: {
                    Text("Streaming availability")
                } footer: {
                    Text("Which country's streaming services to show. Changing this refreshes your shows.")
                }

                Section {
                    Toggle("Air-date alerts", isOn: $notificationsEnabled)
                        .tint(Theme.tonight)

                    if notificationsEnabled {
                        Toggle("Hide details", isOn: $privateNotifications)
                            .tint(Theme.tonight)

                        Picker("Alert me at", selection: $notificationHour) {
                            ForEach(Array(stride(from: 7, through: 22, by: 1)), id: \.self) { hour in
                                Text(label(for: hour)).tag(hour)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(privateNotifications
                         ? "Alerts won't name the show, so nothing shows on your lock screen. One alert per day rather than one per show."
                         : "TMDB publishes air dates without times, so alerts fire at the hour you choose on the day a show airs.")
                }

                if !ignored.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isShowingIgnored) {
                            ForEach(ignored) { item in
                                HStack(spacing: 10) {
                                    Poster(path: item.posterPath, width: 28, height: 42, radius: 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .foregroundStyle(Theme.primary)
                                        Text(item.kind == .tv ? "Show" : "Film")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.tertiary)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets { context.delete(ignored[index]) }
                            }
                        } label: {
                            HStack {
                                Text("Not interested")
                                    .foregroundStyle(Theme.primary)
                                Spacer()
                                Text("\(ignored.count)")
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.tertiary)
                            }
                        }
                    } footer: {
                        Text("Hidden from suggestions. Swipe one to put it back.")
                    }
                }

                Section {
                    Toggle("Add to Reminders automatically", isOn: $autoReminders)
                        .tint(Theme.free)
                } footer: {
                    Text("Writes a reminder for every show with a confirmed date, and moves it if the date changes. Needs Reminders access.")
                }

                Section {
                    Button {
                        Task { await presentHouseholdShare() }
                    } label: {
                        HStack {
                            Text("Invite to household list")
                            if isLoadingHouseholdShare {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoadingHouseholdShare)
                } footer: {
                    Text("Creates the household list if it doesn't exist yet, and opens the invite sheet — send the link to whoever you want sharing the list. CloudKit's own round trip can take a while, especially soon after setup changes.")
                }

                Section {
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .sheet(isPresented: $isShowingHouseholdShare) {
                if let householdShare {
                    CloudSharingView(share: householdShare, container: .default())
                }
            }
            .alert(
                "Couldn't share",
                isPresented: Binding(
                    get: { householdShareError != nil },
                    set: { if !$0 { householdShareError = nil } }
                )
            ) {
                Button("OK") { householdShareError = nil }
            } message: {
                Text(householdShareError ?? "")
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                Task {
                    if enabled, await Notifications.requestPermission() == false {
                        notificationsEnabled = false
                        return
                    }
                    await Notifications.reschedule(for: shows)
                }
            }
            .onChange(of: notificationHour) { _, _ in
                Task { await Notifications.reschedule(for: shows) }
            }
            .onChange(of: privateNotifications) { _, _ in
                Task { await Notifications.reschedule(for: shows) }
            }
            .onChange(of: autoReminders) { _, enabled in
                guard enabled else { return }
                Task { await ReminderSync.sync(shows) }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if region != original { onRegionChanged() }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Ready to watch

/// Stays highlighted until it's marked watched or dismissed.
struct PendingEpisodeCard: View {
    let episode: PendingEpisode
    let onWatched: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Poster(path: episode.posterPath, width: 44, height: 66, radius: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.showName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                Text(episode.label)
                    .font(.footnote)
                    .foregroundStyle(Theme.unwatched)
                    .lineLimit(1)
                Text(episode.airedSummary)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                Button(action: onWatched) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.free)
                }
                .accessibilityLabel("Mark watched")

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
            Rectangle().fill(Theme.unwatched).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 8)
    }
}
