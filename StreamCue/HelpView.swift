import SwiftUI

/// Plain answers to the things that are genuinely non-obvious, most of which
/// come down to what TMDB does and doesn't publish.
struct HelpView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private struct Topic: Identifiable {
        let id = UUID()
        let name: String
        let entries: [Entry]
    }

    private let topics: [Topic] = [
        Topic(name: "Adding things", entries: [
            Entry(
                question: "How do I add a show or film?",
                answer: "Three ways. The + button on the Shows or Movies tab searches by title. The Discover tab suggests things based on what you already track. And the magnifying glass in Discover lets you look up a person or a studio and browse everything they've worked on."
            ),
            Entry(
                question: "Why doesn't tapping a poster add it?",
                answer: "It opens a preview first — description, rating, and where it's streaming — so you can decide. Nothing is added until you press the button at the bottom of that sheet."
            ),
            Entry(
                question: "How do I stop something being suggested?",
                answer: "Open its preview and tap Not interested. It disappears from every suggestion list. To undo it, Settings has a Not interested section — swipe an entry to put it back."
            )
        ]),

        Topic(name: "Dates and episodes", entries: [
            Entry(
                question: "Why does a show say “returning — no date announced”?",
                answer: "Because no date has been announced. Air dates come from TMDB, which only has one once the network publishes it. The app can't know earlier than the broadcaster says."
            ),
            Entry(
                question: "A date looks like it's a day out.",
                answer: "Dates are the original network's air date, which isn't always the day it appears where you are. A UK series you watch a day later, or something that drops at 3am, will legitimately sit on a different day. There's no time attached to the date at all — only the day."
            ),
            Entry(
                question: "A show reaches me on a different day.",
                answer: "Open it and use the day offset on the Schedule section. It shifts that show's dates everywhere — the list, alerts and reminders all follow it. Episodes already in Ready to watch keep the date they were recorded with."
            ),
            Entry(
                question: "What is “Ready to watch”?",
                answer: "Episodes that have already aired and you haven't marked off. The green check means watched, the ✕ means skip it. Either one clears it from the list. It only looks back 30 days, and clears entries older than 60."
            ),
            Entry(
                question: "Why is “Up next” showing when nothing is on tonight?",
                answer: "So the screen always has a focal point. Airing today gets the colour bars down its edge; Up next is just the soonest thing coming, without them."
            )
        ]),

        Topic(name: "Where to watch", entries: [
            Entry(
                question: "What does “Free” mean?",
                answer: "Free to watch without a subscription in your country, including services that are free with ads. It's separate from something being included in a subscription you already pay for, which shows in grey."
            ),
            Entry(
                question: "Nothing is listed for a show I know is streaming.",
                answer: "Availability is per country, so check the country setting in Settings. It's also possible the show hasn't been refreshed since you added it — pull down on the list."
            ),
            Entry(
                question: "What does the Services tab do?",
                answer: "You tell it what you subscribe to, and it suggests things on each of those services, weighted toward the genres you already watch. Picking services also lets you filter your own list by them."
            )
        ]),

        Topic(name: "Alerts and reminders", entries: [
            Entry(
                question: "When do notifications arrive?",
                answer: "On the day a show airs, at the hour you choose in Settings — not at broadcast time. Air dates have no time attached, so there's nothing more precise to fire on."
            ),
            Entry(
                question: "What's the difference between alerts and Reminders?",
                answer: "Alerts are notifications from this app. Add to Reminders writes an entry into Apple's Reminders app instead, which syncs to your other devices and stays there even if you delete this app. The menu on the Shows tab can add one for everything with a confirmed date at once."
            ),
            Entry(
                question: "I turned alerts on but nothing happens.",
                answer: "They only fire for shows with a known upcoming date. If everything you track is between seasons, there's nothing to schedule."
            )
        ]),

        Topic(name: "Data and refreshing", entries: [
            Entry(
                question: "How often does it update?",
                answer: "When you open the app, if it hasn't checked in the last half hour — and even then only for shows more than six hours old. Pull down on any list, or use Refresh all in the menu, to update everything immediately."
            ),
            Entry(
                question: "Ratings are missing.",
                answer: "IMDb and Rotten Tomatoes scores are fetched once per title and coverage for television is patchy — Rotten Tomatoes especially. Where none is available you'll see TMDB's own score instead."
            ),
            Entry(
                question: "Where is my data kept?",
                answer: "On this device. Nothing is uploaded and there's no account."
            ),
            Entry(
                question: "Discover looks empty.",
                answer: "Anything you already track, or have marked Not interested, is hidden. If you've added a lot, a feed can thin out — scroll to load more, or try another one."
            )
        ])
    ]

    var body: some View {
        List {
            ForEach(topics) { topic in
                Section(topic.name) {
                    ForEach(topic.entries) { entry in
                        DisclosureGroup {
                            Text(entry.answer)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .padding(.vertical, 4)
                        } label: {
                            Text(entry.question)
                                .font(.subheadline)
                                .foregroundStyle(Theme.primary)
                        }
                    }
                }
            }

            Section {
                Text("Show and film data from TMDB. Ratings from OMDb where available.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}
