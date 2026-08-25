import SwiftUI
import Observation
import WidgetKit

struct Section: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var lines: [String]
}

struct Person: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var cat: String
    var meta: String
    var date: Date
    var summary: String
    var place: String
    var archived = false
    var avatar: Data?
    var photos: [Data] = []
    var sections: [Section] = []

    var initial: String { String(name.prefix(1)) }
    var haystack: String { ([name, summary, meta] + sections.flatMap(\.lines)).joined(separator: " ") }
}

struct Category: Codable, Hashable, Identifiable {
    var id: String
    var label: String
}

enum SortMode: String, Codable, CaseIterable {
    case recent, name, manual
    var label: String { switch self { case .recent: "Recent"; case .name: "Name"; case .manual: "Manual" } }
}

enum ThemeMode: String, Codable, CaseIterable {
    case system, light, dark
    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

struct Prefs: Codable {
    var theme: ThemeMode = .system
    var sort: SortMode = .recent
    var gallery = false
    var cat = "all"
    var onboarded = false
    var notifications = true
    var icloud = true
    /// Empty until the person says otherwise. It used to ship as "Auguste", which
    /// greeted every single user on the App Store by the developer's name.
    var name = ""
}

@Observable
final class Store {
    var people: [Person] = []
    var categories: [Category] = []
    var order: [Int] = []
    var prefs = Prefs()
    private var nextID = 1
    private var tidied = false   // the launch filing pass runs once per session

    /// Selection state for the gallery's multi-select mode.
    var selecting = false
    var selection: Set<Int> = []

    /// The App Group container, so the widget process can read the same file.
    /// Falls back to Documents when the group is missing — an unsigned build, or
    /// a provisioning profile without the capability — rather than losing notes.
    private var url: URL {
        let box = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.metwho.app")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return box.appendingPathComponent("metwho.json")
    }

    private struct Snapshot: Codable {
        var people: [Person]; var categories: [Category]; var order: [Int]
        var prefs: Prefs; var nextID: Int
        var updatedAt: Date = .distantPast
    }

    private var updatedAt: Date = .distantPast

    init() {
        load()
        CloudSync.start { [weak self] in self?.adoptRemote() }
        adoptRemote()
    }

    func load() {
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            people = s.people; categories = s.categories; order = s.order
            prefs = s.prefs; nextID = s.nextID; updatedAt = s.updatedAt
        } else {
            firstRun()
        }
    }

    /// A new install is empty. It used to arrive holding six invented French
    /// people under the heading "6 people you've met", which is both a lie to the
    /// user and demo content in a shipped binary.
    private func firstRun() {
        categories = [Category(id: "work", label: "Work"),
                      Category(id: "private", label: "Private"),
                      Category(id: "family", label: "Family")]
        people = []; order = []; nextID = 1
        prefs = Prefs()
    }

    func save() {
        updatedAt = .now
        let s = Snapshot(people: people, categories: categories, order: order,
                         prefs: prefs, nextID: nextID, updatedAt: updatedAt)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()

        guard prefs.icloud else { return }
        // strip the heavy fields rather than the whole person: the text is the
        // part worth having on the other device
        var light = s
        light.people = light.people.map { p in
            var copy = p; copy.avatar = nil; copy.photos = []; return copy
        }
        if let slim = try? JSONEncoder().encode(light) {
            CloudSync.push(slim, at: updatedAt)
        }
    }

    /// Takes the remote snapshot when it is newer, keeping every image this
    /// device already holds — those never went up, so they can only come from here.
    private func adoptRemote() {
        guard prefs.icloud,
              let data = CloudSync.pull(newerThan: updatedAt),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }

        let localImages = Dictionary(uniqueKeysWithValues: people.map { ($0.id, ($0.avatar, $0.photos)) })
        people = s.people.map { p in
            var copy = p
            if let held = localImages[p.id] { copy.avatar = held.0; copy.photos = held.1 }
            return copy
        }
        categories = s.categories; order = s.order; nextID = max(nextID, s.nextID)
        updatedAt = s.updatedAt

        // theme and the API-key-free half of prefs travel; the local sync switch
        // must not be flipped by the very sync it controls
        let keepCloud = prefs.icloud
        prefs = s.prefs
        prefs.icloud = keepCloud

        let out = Snapshot(people: people, categories: categories, order: order,
                           prefs: prefs, nextID: nextID, updatedAt: updatedAt)
        try? JSONEncoder().encode(out).write(to: url, options: .atomic)
    }

    /// Back to an empty app, the way it arrives from the App Store.
    func reset() {
        try? FileManager.default.removeItem(at: url)
        selecting = false; selection = []
        firstRun(); save()
    }

    /// Sample people, on request only, so the app can be looked around before
    /// there is anything real in it.
    func loadSamples() {
        seed()
        save()
    }

    // MARK: - Derived

    func person(_ id: Int) -> Person? { people.first { $0.id == id } }
    func index(_ id: Int) -> Int? { people.firstIndex { $0.id == id } }

    /// `all` filters and `unsorted` catches orphans — neither is the user's to delete.
    var visibleCategories: [Category] {
        var out = [Category(id: "all", label: "All")] + categories
        if people.contains(where: { !$0.archived && $0.cat == "unsorted" }) {
            out.append(Category(id: "unsorted", label: "Unsorted"))
        }
        return out
    }
    func label(_ id: String) -> String { visibleCategories.first { $0.id == id }?.label ?? "All" }
    func count(_ id: String) -> Int {
        people.filter { !$0.archived && (id == "all" || $0.cat == id) }.count
    }

    var feed: [Person] {
        let base = order.compactMap(person).filter {
            !$0.archived && (prefs.cat == "all" || $0.cat == prefs.cat)
        }
        switch prefs.sort {
        case .manual: return base
        case .name:   return base.sorted { $0.name < $1.name }
        case .recent: return base.sorted { $0.date > $1.date }
        }
    }

    var archived: [Person] { people.filter(\.archived) }

    func search(_ term: String) -> [(person: Person, line: String)] {
        let t = term.lowercased()
        guard !t.isEmpty else { return [] }
        return people.compactMap { p in
            let fields = [p.name, p.summary, p.meta] + p.sections.flatMap(\.lines)
            guard let hit = fields.first(where: { $0.lowercased().contains(t) }) else { return nil }
            return (p, hit)
        }
    }

    var placesByCity: [(city: String, people: [Person])] {
        Dictionary(grouping: people.filter { !$0.archived && !$0.place.isEmpty }, by: \.place)
            .map { (city: $0.key, people: $0.value) }
            .sorted { $0.people.count > $1.people.count }
    }

    // MARK: - Mutations

    func update(_ p: Person) {
        guard let i = index(p.id) else { return }
        people[i] = p
        save()
    }

    func add(_ p: Person) {
        people.insert(p, at: 0)
        order.insert(p.id, at: 0)
        save()
    }

    func archive(_ id: Int) { setArchived(id, true) }
    func restore(_ id: Int) { setArchived(id, false) }
    func setArchived(_ id: Int, _ v: Bool) {
        guard let i = index(id) else { return }
        people[i].archived = v
        save()
    }

    @discardableResult
    func delete(_ id: Int) -> (Person, Int)? {
        guard let i = index(id) else { return nil }
        let gone = people.remove(at: i)
        let at = order.firstIndex(of: id) ?? 0
        order.removeAll { $0 == id }
        save()
        return (gone, at)
    }

    func reinsert(_ p: Person, at slot: Int) {
        people.append(p)
        order.insert(p.id, at: min(slot, order.count))
        save()
    }

    func addCategory(_ raw: String) {
        let label = raw.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let id = label.lowercased().replacingOccurrences(of: " ", with: "-")
        guard !categories.contains(where: { $0.id == id }) else { return }
        categories.append(Category(id: id, label: label))
        save()
    }

    /// A category can go away; the people in it cannot. They fall to Unsorted.
    func deleteCategory(_ id: String) {
        for i in people.indices where people[i].cat == id { people[i].cat = "unsorted" }
        categories.removeAll { $0.id == id }
        if prefs.cat == id { prefs.cat = "all" }
        save()
    }

    func move(_ ids: some Collection<Int>, to cat: String) {
        for i in people.indices where ids.contains(people[i].id) { people[i].cat = cat }
        save()
    }

    func reorder(from source: IndexSet, to destination: Int) {
        var ids = feed.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        order = ids + order.filter { !ids.contains($0) }
        // dragging IS the statement that you want your own order
        if prefs.sort != .manual { prefs.sort = .manual }
        save()
    }

    func nextIdentifier() -> Int { defer { nextID += 1 }; return nextID }

    // MARK: - Capture parsing
    // A small heuristic, not a model. It splits a dictated sentence into a name,
    // a place, and up to three sections. Wrong often enough that every line is
    // editable afterwards — which is why they are.
    func parse(_ raw: String) -> Person? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !text.isEmpty else { return nil }

        var name: String, rest: String
        if let comma = text.firstIndex(of: ","), text.distance(from: text.startIndex, to: comma) < 40 {
            name = String(text[text.startIndex..<comma])
            rest = String(text[text.index(after: comma)...])
        } else {
            let words = text.split(separator: " ")
            name = words.prefix(2).joined(separator: " ")
            rest = words.dropFirst(2).joined(separator: " ")
        }
        name = name.replacingOccurrences(of: "^(i )?(met|saw|ran into) ", with: "",
                                         options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Someone" }

        let sentences = rest.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let nextVerbs = ["send", "ask", "introduce", "follow", "email", "call", "take", "invite", "remind", "share", "book", "reply"]
        let next = sentences.filter { s in nextVerbs.contains(where: { s.lowercased().hasPrefix($0) }) }
        let whereMet = sentences.first { s in
            !next.contains(s) && s.range(of: "\\b(at|in|on|during|after|before)\\b",
                                         options: [.regularExpression, .caseInsensitive]) != nil
        }
        let does = sentences.filter { $0 != whereMet && !next.contains($0) }

        var place = ""
        if let m = (whereMet ?? text).range(of: "(?:at|in) ([A-ZÀ-Ý][\\wÀ-ÿ'’-]*(?: [A-ZÀ-Ý][\\wÀ-ÿ'’-]*)?)",
                                            options: .regularExpression) {
            place = String((whereMet ?? text)[m])
                .replacingOccurrences(of: "^(at|in) ", with: "", options: [.regularExpression, .caseInsensitive])
        }

        var sections: [Section] = []
        if let whereMet { sections.append(Section(title: "Where you met", lines: [whereMet])) }
        if !does.isEmpty { sections.append(Section(title: "What they do", lines: does)) }
        if !next.isEmpty { sections.append(Section(title: "Next step", lines: next)) }
        if sections.isEmpty { sections.append(Section(title: "Memory", lines: [text])) }

        let df = DateFormatter(); df.dateFormat = "MMM d"
        return Person(id: nextIdentifier(), name: name,
                      cat: prefs.cat == "all" ? "unsorted" : prefs.cat,
                      meta: "\(place.isEmpty ? "Met" : place) · \(df.string(from: .now))",
                      date: .now,
                      summary: String((does.first ?? whereMet ?? text).prefix(120)),
                      place: place, sections: sections)
    }

    // MARK: - Refinement

    /// Replaces the heuristic's guesses with what the sentence actually said.
    ///
    /// The heuristic result is already saved and on screen when this runs, so the
    /// card fills itself in a beat later rather than making anyone wait. That
    /// order is the whole trick: a spinner here would announce the model, and the
    /// model is meant to be invisible.
    @MainActor
    func refine(_ id: Int, from raw: String) async {
        guard let draft = await Intelligence.shared.profile(from: raw, categories: categories.map(\.id)),
              var p = person(id) else { return }

        if !draft.name.isEmpty { p.name = draft.name }
        if !draft.place.isEmpty { p.place = draft.place }
        if !draft.summary.isEmpty { p.summary = draft.summary }

        var sections: [Section] = []
        if !draft.whereMet.isEmpty { sections.append(Section(title: "Where you met", lines: [draft.whereMet])) }
        if !draft.facts.isEmpty { sections.append(Section(title: "What they do", lines: draft.facts)) }
        if !draft.nextSteps.isEmpty { sections.append(Section(title: "Next step", lines: draft.nextSteps)) }
        if !sections.isEmpty { p.sections = sections }

        // An explicit filter is the user saying where this belongs; only fill in
        // the ones the heuristic dropped into Unsorted.
        if p.cat == "unsorted", categories.contains(where: { $0.id == draft.category }) {
            p.cat = draft.category
        }

        let df = DateFormatter(); df.dateFormat = "MMM d"
        p.meta = "\(p.place.isEmpty ? "Met" : p.place) · \(df.string(from: p.date))"

        update(p)
    }

    // MARK: - Contacts

    /// Imports address-book entries as cards rather than as placeholders.
    ///
    /// Everyone is added first with what the address book literally said, so the
    /// import completes even with no key and no signal. The write-up lands on top
    /// afterwards, in one call for the whole batch.
    @MainActor
    func importContacts(_ seeds: [ContactSeed]) async {
        let df = DateFormatter(); df.dateFormat = "MMM d"
        let stamp = df.string(from: .now)

        var added: [String: Int] = [:]
        for seed in seeds where !people.contains(where: { $0.name == seed.name }) {
            let id = nextIdentifier()
            let detail = [seed.role, seed.org].filter { !$0.isEmpty }.joined(separator: " at ")
            add(Person(id: id, name: seed.name, cat: "unsorted",
                       meta: "\(seed.city.isEmpty ? "From Contacts" : seed.city) · \(stamp)",
                       date: .now,
                       summary: detail.isEmpty ? "" : detail,
                       place: seed.city,
                       sections: detail.isEmpty
                           ? [Section(title: "Memory", lines: ["Nothing captured yet. Tap + to add what you remember."])]
                           : [Section(title: "What they do", lines: [detail])]))
            added[seed.name] = id
        }
        guard !added.isEmpty else { return }

        guard let drafts = await Intelligence.shared.enrich(seeds, categories: categories.map(\.id))
        else { return }

        for draft in drafts {
            guard let id = added[draft.name], var p = person(id) else { continue }
            if !draft.summary.isEmpty { p.summary = draft.summary }
            if !draft.place.isEmpty {
                p.place = draft.place
                p.meta = "\(draft.place) · \(stamp)"
            }
            if !draft.facts.isEmpty {
                p.sections = [Section(title: "What they do", lines: draft.facts)]
            }
            if categories.contains(where: { $0.id == draft.category }) { p.cat = draft.category }
            update(p)
        }
    }

    /// Adds something new to a person, under whichever heading it belongs to.
    ///
    /// The line lands immediately under the closest existing heading so nothing
    /// is lost if the model is unreachable; when it answers, the line moves to
    /// the heading it named and gets the tidier wording.
    @MainActor
    func addLine(_ raw: String, to id: Int) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var p = person(id) else { return }

        // lands under the nearest heading first, so nothing is lost if the model
        // is unreachable; refile moves it once an answer comes back
        let fallback = p.sections.last?.title ?? "Memory"
        append(text, under: fallback, to: &p)
        update(p)
        await refile(text, of: id)
    }

    /// Moves a line to the heading it belongs under, in the wording the card
    /// speaks in.
    ///
    /// Runs on anything written into a person — the free-write sheet and an
    /// edited line alike. Writing "he only shoots film" under "Where you met"
    /// should not leave it there just because that is the row you happened to be
    /// looking at; picking the heading was never the user's job.
    ///
    /// A no-op when the line is already right, so an edit that only fixes a typo
    /// does not make the row jump.
    @MainActor
    func refile(_ text: String, of id: Int) async {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.aiQuestion == nil, let p = person(id),
              let filed = await Intelligence.shared.filed(line, for: p),
              var fresh = person(id) else { return }

        let home = fresh.sections.first { $0.lines.contains(line) }
        if home?.title.lowercased() == filed.heading.lowercased(), filed.line == line { return }

        for i in fresh.sections.indices {
            fresh.sections[i].lines.removeAll { $0 == line }
        }
        fresh.sections.removeAll { $0.lines.isEmpty }
        append(filed.line, under: filed.heading, to: &fresh)
        fresh.summary = String(fresh.sections.flatMap(\.lines).joined(separator: " ").prefix(120))
        withAnimation(.smooth) { update(fresh) }
    }

    private func append(_ line: String, under heading: String, to p: inout Person) {
        if let i = p.sections.firstIndex(where: { $0.title.lowercased() == heading.lowercased() }) {
            p.sections[i].lines.append(line)
        } else {
            p.sections.append(Section(title: heading, lines: [line]))
        }
    }

    // MARK: - Housekeeping

    /// Files whatever is sitting in Unsorted, quietly, on launch.
    ///
    /// Capped and one-shot per session: this is meant to be the drawer being
    /// tidier than you left it, not a background job anyone can feel.
    @MainActor
    func tidy() async {
        guard !tidied else { return }
        tidied = true

        await repairNames()

        let targets = Array(people.filter { !$0.archived && $0.cat == "unsorted" }.prefix(20))
        guard targets.count > 0, !categories.isEmpty else { return }

        guard let filed = await Intelligence.shared.sort(targets, into: categories.map(\.id))
        else { return }
        for (id, cat) in filed {
            guard let i = index(id), people[i].cat == "unsorted" else { continue }
            people[i].cat = cat
        }
        save()
    }

    /// Re-reads the cards the heuristic mangled before there was anything better.
    ///
    /// "J'ai rencontré jean chauvin" is a name the old parser produced by taking
    /// the first words of a sentence, and nothing was ever going to fix it: the
    /// capture-time pass only runs at capture time. The original sentence is still
    /// sitting in the card's own lines, so it gets read again properly.
    ///
    /// Capped per session, because every one of these is a request.
    @MainActor
    private func repairNames() async {
        let broken = people.filter { !$0.archived && $0.name.readsLikeASentence }.prefix(5)
        for p in broken {
            let raw = ([p.summary] + p.sections.flatMap(\.lines))
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard raw.count > 10 else { continue }
            await refine(p.id, from: raw)
        }
    }

    // MARK: - Seed

    private func seed() {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        func d(_ s: String) -> Date { df.date(from: s) ?? .now }
        nextID = 9
        categories = [Category(id: "work", label: "Work"),
                      Category(id: "private", label: "Private"),
                      Category(id: "family", label: "Family")]
        prefs = Prefs()
        people = [
            Person(id: 1, name: "Clara Vasseur", cat: "work", meta: "Devoxx · Jun 12", date: d("2026-06-12"),
                   summary: "Building a recipe app, looking for a product designer.", place: "Paris",
                   sections: [Section(title: "Where you met", lines: ["In the line for the Algolia stand. Twenty minutes on vector search."]),
                              Section(title: "What she does", lines: ["Building a recipe app.", "Looking for a product designer."]),
                              Section(title: "Next step", lines: ["Send her Léa’s contact."])]),
            Person(id: 2, name: "Hugo Trémaux", cat: "private", meta: "Dinner at Léa's · Jun 3", date: d("2026-06-03"),
                   summary: "Back from two years in Lisbon. Photographs port architecture.", place: "Lisbon",
                   sections: [Section(title: "Where you met", lines: ["Léa sat us together. He'd landed that morning."]),
                              Section(title: "What he does", lines: ["Photographs port architecture.", "Has been at Jacquemus since January."]),
                              Section(title: "Next step", lines: ["Ask to see the Lisbon series."])]),
            Person(id: 3, name: "Naïma Belkacem", cat: "work", meta: "Station F · May 28", date: d("2026-05-28"),
                   summary: "Raising a Series A in logistics. Running a marathon in April.", place: "Paris",
                   sections: [Section(title: "Where you met", lines: ["Same coworking floor, waiting on the same coffee machine."]),
                              Section(title: "What she does", lines: ["Raising a Series A in logistics.", "Running a marathon in April."]),
                              Section(title: "Next step", lines: ["Send the deck template."])]),
            Person(id: 4, name: "Tomás Ferreira", cat: "private", meta: "Paris–Porto flight · May 19", date: d("2026-05-19"),
                   summary: "Winemaker in the Douro. Offered to show us around.", place: "Porto",
                   sections: [Section(title: "Where you met", lines: ["Seat 14C. Talked the whole flight."]),
                              Section(title: "What he does", lines: ["Winemaker in the Douro valley."]),
                              Section(title: "Next step", lines: ["Take him up on the visit before September."])]),
            Person(id: 5, name: "Sofia Lindqvist", cat: "work", meta: "Paris Fashion Week · May 2", date: d("2026-05-02"),
                   summary: "Styles shoots for Vogue Scandinavia. Moving to Paris in the autumn.", place: "Stockholm",
                   sections: [Section(title: "Where you met", lines: ["Backstage, waiting out the rain."]),
                              Section(title: "What she does", lines: ["Styles shoots for Vogue Scandinavia.", "Moving to Paris in the autumn."]),
                              Section(title: "Next step", lines: ["Introduce her to Hugo."])]),
            Person(id: 6, name: "Marc Oberlé", cat: "family", meta: "Cousin's wedding · Apr 18", date: d("2026-04-18"),
                   summary: "Second cousin. Restores wooden boats in Brittany.", place: "Paris",
                   sections: [Section(title: "Where you met", lines: ["Same table at the wedding, all evening."]),
                              Section(title: "What he does", lines: ["Restores wooden boats in Brittany."]),
                              Section(title: "Next step", lines: ["Send the photo from the ceremony."])]),
            Person(id: 7, name: "Ana Ruiz", cat: "work", meta: "Lisbon meetup · Apr 4", date: d("2026-04-04"),
                   summary: "Runs a design studio for cultural institutions.", place: "Lisbon", archived: true,
                   sections: [Section(title: "Where you met", lines: ["Spoke after her talk."]),
                              Section(title: "What she does", lines: ["Runs a design studio for museums and archives."])]),
            Person(id: 8, name: "Jonas Weiss", cat: "private", meta: "Climbing gym · Mar 22", date: d("2026-03-22"),
                   summary: "Belayed for me on the overhang. Teaches physics.", place: "New York", archived: true,
                   sections: [Section(title: "Where you met", lines: ["He belayed for me on the overhang route."]),
                              Section(title: "What he does", lines: ["Teaches physics at a lycée."])]),
        ]
        order = people.map(\.id)
    }
}
