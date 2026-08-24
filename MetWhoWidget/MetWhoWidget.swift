import WidgetKit
import SwiftUI

// MARK: - Shared data
//
// The extension deliberately does not link the app's `Store`: that type reaches
// into speech, purchases, contacts and the network, none of which belong in a
// widget process. It reads the same JSON file out of the shared App Group and
// decodes only the four fields a card can show.

fileprivate struct Shared: Decodable {
    struct Person: Decodable {
        var id: Int
        var name: String
        var meta: String
        var summary: String
        var archived: Bool
        var date: Date
    }
    var people: [Person]
}

fileprivate enum Feed {
    static let group = "group.com.metwho.app"

    static func read() -> [Shared.Person] {
        guard let box = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("metwho.json"),
              let data = try? Data(contentsOf: box),
              let snapshot = try? JSONDecoder().decode(Shared.self, from: data)
        else { return [] }
        return snapshot.people
            .filter { !$0.archived }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    fileprivate let people: [Shared.Person]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, people: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, people: Feed.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // nothing here changes on its own; the app reloads timelines when it
        // writes, so the only refresh needed is a slow safety net
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now
        completion(Timeline(entries: [Entry(date: .now, people: Feed.read())], policy: .after(next)))
    }
}

// MARK: - Views

struct MetWhoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    fileprivate var shown: [Shared.Person] {
        Array(entry.people.prefix(family == .systemSmall ? 1 : 3))
    }

    var body: some View {
        Group {
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.2.fill").font(.system(size: 20, weight: .bold))
                    Text("Nobody yet").font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 10) {
                    ForEach(shown, id: \.id) { person in
                        Link(destination: URL(string: "metwho://person/\(person.id)")!) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.system(size: family == .systemSmall ? 15 : 14, weight: .heavy))
                                    .lineLimit(1)
                                Text(person.summary.isEmpty ? person.meta : person.summary)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(family == .systemSmall ? 3 : 1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

@main
struct MetWhoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetWhoWidget", provider: Provider()) { entry in
            MetWhoWidgetView(entry: entry)
        }
        .configurationDisplayName("People")
        .description("The people you met most recently.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
