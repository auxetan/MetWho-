import Foundation

/// What the app does with a brain once it has one.
///
/// Four capabilities, and only the last of them is something the user asks for
/// by name:
///
/// - `profile` turns a spoken sentence into a filled-in card. This is the one
///   that matters: "J'ai rencontré Jean Chauvin, on a discuté à la Palma…"
///   became a person *named* "J'ai rencontré jean chauvin" under the heuristic,
///   with the whole sentence dumped into "Where you met" and no place at all.
/// - `answer` makes the search box do what the onboarding promises.
/// - `brief` picks the three lines worth reading before you walk up to someone.
/// - `ask` is `@AI` inside a note, the one visible seam.
///
/// Every call returns `nil` rather than throwing. No brain, no network, a model
/// having a bad day — all of it lands as "keep what the heuristic gave you". A
/// contact app that loses a note because a server was down is worse than a
/// contact app with a clumsy heuristic.
@MainActor
final class Intelligence {

    static let shared = Intelligence()
    private init() {}

    private var brain: Brain? { AIConfig.shared.brain }
    var isReady: Bool { brain != nil }

    /// Given to the model on every question. Without it, "moving in the autumn"
    /// is a plan forever — the model has no way to know that autumn has been and
    /// gone. Fixed locale so the format never depends on the phone's region.
    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: .now)
    }

    // MARK: - Capture

    /// Reads one dictated or typed sentence into a structured profile.
    ///
    /// Works in whatever language the note was written in — the answer comes back
    /// in that language too, so a French note does not acquire English section
    /// text.
    func profile(from raw: String, categories: [String]) async -> ProfileDraft? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 2, let brain else { return nil }

        let known = categories.isEmpty ? "work, private, family" : categories.joined(separator: ", ")
        let system = """
        You turn one note about meeting someone into a contact card.

        Reply with JSON only, no prose, no code fence:
        {"name":"","place":"","category":"","summary":"","whereMet":"","facts":[],"nextSteps":[]}

        Rules:
        - "name": the person's name only, properly capitalised. Strip everything \
        that is not the name: "J'ai rencontré jean chauvin" is the name \
        "Jean Chauvin". Empty string if no name was given.
        - "place": the town, venue or event where the meeting happened, name only, \
        no preposition. Prefer the most specific real place named. Empty if none.
        - "category": one of \(known). Pick from context — a colleague or a \
        conference contact is work, a friend or someone met socially is private, \
        a relative is family.
        - "summary": who this person is, one sentence, under twelve words.
        - "whereMet": how and where the meeting happened, one sentence. Empty if \
        the note does not say.
        - "facts": what the person does or has going on. One idea per string, at \
        most four, written as clean short statements in the third person.
        - "nextSteps": what the writer owes or intends to do. At most three. \
        Empty if the note mentions none.
        - Write every value in the same language as the note.
        - Tidy the wording and fix casing, but invent nothing. If the note does \
        not say it, leave the field empty.
        """

        guard let out: RemoteProfile = await decode(brain, system: system, user: text, temperature: 0.2)
        else { return nil }

        return ProfileDraft(
            name: out.name.orEmpty.trimmed,
            place: out.place.orEmpty.trimmed,
            summary: out.summary.orEmpty.trimmed,
            whereMet: out.whereMet.orEmpty.trimmed,
            facts: (out.facts ?? []).cleaned,
            nextSteps: (out.nextSteps ?? []).cleaned,
            category: out.category.orEmpty.trimmed.lowercased()
        )
    }

    // MARK: - Contacts

    /// Turns address-book entries into cards worth keeping.
    ///
    /// A contact gives you a name, maybe an employer, maybe a job title. On its
    /// own that produces a row reading "Imported from Contacts. No memories yet."
    /// — which is a to-do, not a memory. This writes the one line those fields
    /// actually support and files the person under the right heading.
    ///
    /// One call for the whole batch: forty contacts is forty round trips
    /// otherwise, and the user is watching a spinner for all of them.
    func enrich(_ seeds: [ContactSeed], categories: [String]) async -> [ContactDraft]? {
        guard !seeds.isEmpty, let brain else { return nil }
        let known = categories.isEmpty ? "work, private, family" : categories.joined(separator: ", ")

        let listing = seeds.enumerated().map { i, s in
            var line = "[\(i)] \(s.name)"
            if !s.role.isEmpty { line += " — \(s.role)" }
            if !s.org.isEmpty { line += " — \(s.org)" }
            if !s.city.isEmpty { line += " — \(s.city)" }
            return line
        }.joined(separator: "\n")

        let system = """
        You file address-book entries into a contact app.

        Reply with JSON only, no prose, no code fence:
        {"cards":[{"i":0,"category":"","summary":"","place":"","facts":[]}]}

        Rules:
        - "i" is the number in square brackets for that entry.
        - "category": one of \(known). Someone with an employer or a job title is \
        work unless the entry says otherwise. Someone with neither is private. \
        Only file as family when the entry actually indicates a relative.
        - "summary": one sentence under twelve words built strictly from the \
        fields given. If there is nothing but a name, use an empty string rather \
        than inventing a life.
        - "place": the city if one is given, otherwise empty.
        - "facts": at most two short third-person statements, again only from the \
        fields given. Empty when the entry is just a name.
        - Never guess a job, a company, or a relationship that is not written down.
        - Write in the same language as the entries.
        """

        guard let out: RemoteCards = await decode(brain, system: system, user: listing, temperature: 0.2)
        else { return nil }

        return (out.cards ?? []).compactMap { card in
            guard let i = card.i, seeds.indices.contains(i) else { return nil }
            return ContactDraft(
                name: seeds[i].name,
                category: card.category.orEmpty.trimmed.lowercased(),
                summary: card.summary.orEmpty.trimmed,
                place: card.place.orEmpty.trimmed,
                facts: (card.facts ?? []).cleaned
            )
        }
    }

    // MARK: - Housekeeping

    /// Files the people who never got filed.
    ///
    /// Runs on launch against whatever is sitting in Unsorted. Nothing in the UI
    /// reports it — the drawer is simply less of a mess than it was, which is the
    /// point.
    func sort(_ people: [Person], into categories: [String]) async -> [Int: String]? {
        guard !people.isEmpty, !categories.isEmpty, let brain else { return nil }

        let listing = people.map(\.dossier).joined(separator: "\n")
        let system = """
        You file people into categories in a contact app.

        Reply with JSON only, no prose, no code fence:
        {"filed":[{"id":0,"category":""}]}

        Rules:
        - "id" is the number in square brackets at the start of that person's line.
        - "category" is one of: \(categories.joined(separator: ", ")).
        - Leave a person out of the list entirely when their notes do not say \
        enough to file them. A wrong drawer is worse than no drawer.
        """

        guard let out: RemoteFiling = await decode(brain, system: system, user: listing, temperature: 0.1)
        else { return nil }

        let allowed = Set(categories)
        var filed: [Int: String] = [:]
        for row in out.filed ?? [] {
            guard let id = row.id, let cat = row.category?.trimmed.lowercased(),
                  allowed.contains(cat) else { continue }
            filed[id] = cat
        }
        return filed
    }

    // MARK: - Search

    /// Answers a plain-English (or plain-French) question against the notes.
    ///
    /// Substring search cannot match "who works in fashion" against a stylist for
    /// Vogue Scandinavia. Callers merge these hits with the literal ones, so the
    /// result set only ever grows.
    func answer(_ query: String, over people: [Person]) async -> [SearchHit]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count > 2, !people.isEmpty, let brain else { return nil }

        let corpus = people.prefix(60).map(\.dossier).joined(separator: "\n")
        let system = """
        You search someone's notes about people they have met. Today is \(Self.today).

        Reply with JSON only, no prose, no code fence:
        {"hits":[{"id":0,"line":""}]}

        Rules:
        - "id" is the number in square brackets at the start of that person's line.
        - "line" is the sentence from their notes that led you to them, quoted \
        word for word.
        - Match on meaning and on consequence, not on spelling. A stylist for a \
        fashion magazine answers "who works in fashion". Someone noted months ago \
        as "moving to Paris in the autumn" answers "who lives in Paris", because \
        that autumn has passed.
        - Dates matter: a plan made before today has probably happened, and a \
        place someone was leaving is probably not where they are now.
        - Only include people the notes actually point to. An empty list is a good \
        answer when nothing fits — a wrong name is worse than no name.
        - Best match first, at most eight.
        """
        let user = "Notes:\n\(corpus)\n\nQuestion: \(q)"

        guard let out: RemoteAnswer = await decode(brain, system: system, user: user, temperature: 0.1)
        else { return nil }

        let known = Set(people.map(\.id))
        return (out.hits ?? []).compactMap { hit in
            guard let id = hit.id, known.contains(id) else { return nil }
            return SearchHit(id: id, line: hit.line.orEmpty.trimmed)
        }
    }

    // MARK: - Refresher

    /// The ten-second briefing before you see someone again.
    func brief(for person: Person) async -> [String]? {
        let lines = person.sections.flatMap(\.lines)
        guard lines.count > 1, let brain else { return nil }

        let system = """
        You write the note someone reads in the ten seconds before walking up to a \
        person they have met once.

        Reply with JSON only, no prose, no code fence:
        {"lines":["","",""]}

        Rules:
        - Exactly three lines, each under twelve words.
        - Anything the writer promised comes first.
        - Use the notes' own words and the notes' own language. Add nothing.
        - No greeting, no advice, no preamble.
        """
        let user = """
        Person: \(person.name)
        Met: \(person.meta)
        Notes:
        \(lines.map { "- \($0)" }.joined(separator: "\n"))
        """

        guard let out: RemoteBrief = await decode(brain, system: system, user: user, temperature: 0.3)
        else { return nil }
        let cleaned = (out.lines ?? []).cleaned
        return cleaned.isEmpty ? nil : Array(cleaned.prefix(3))
    }

    // MARK: - @AI

    /// Answers a question typed inside a note, in place.
    ///
    /// The only capability the user invokes deliberately, so it is also the only
    /// one allowed to be slow enough to notice. It gets the note being written and
    /// the person it is about, because "what should I ask her about?" is
    /// unanswerable without both.
    /// - Parameters:
    ///   - everyone: the whole address book. "Who is Jean?" is unanswerable from
    ///     the note in front of you — the answer is on a card written months ago,
    ///     so the model gets all of them, not just the one on screen.
    ///   - note: what is being written right now, when there is one.
    ///   - person: the card this note belongs to, when there is one.
    func ask(_ question: String,
             everyone: [Person],
             note: String = "",
             about person: Person? = nil) async -> String? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let brain else { return nil }

        let system = """
        You answer questions about the people someone has met, using the notes \
        they wrote. Today is \(Self.today).

        Rules:
        - Answer in one or two sentences. This goes straight into a note or a \
        results list, not into a chat window.
        - Plain text only. No markdown, no bullets, no preamble, no sign-off.
        - Reply in the language the question is written in.
        - Names in the notes are the ground truth. If someone is asked about by \
        first name only and exactly one person matches, that is them.

        Reason from the notes, do not just match their words:
        - A plan made before today has probably happened. A note from June saying \
        someone was "moving to Paris in the autumn" answers "who lives in Paris" \
        — say they most likely do now, and say which note it came from.
        - A job implies a field: styling shoots for a fashion magazine is working \
        in fashion, a winemaker is working in wine.
        - A place someone was moving away from is probably not where they are now.

        Mark every inference as one. Say "probably", "most likely", "was planning \
        to" — never state a conclusion as something the notes recorded. If the \
        notes give you nothing to reason from, say so in one short sentence \
        rather than guessing.
        """

        var user = "Everyone in the notes:\n"
        user += everyone.prefix(80).map(\.dossier).joined(separator: "\n")
        if let person {
            user += "\n\nThe note being written is about: \(person.name)"
        }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            user += "\n\nThe note so far:\n\(note)"
        }
        user += "\n\nQuestion: \(q)"

        guard let text = try? await brain.reply(system: system, user: user, temperature: 0.4, json: false)
        else { return nil }
        let answer = text.strippedFence.trimmed
        return answer.isEmpty ? nil : answer
    }

    // MARK: - Plumbing

    /// Models add code fences and apologies no matter how firmly they are told
    /// not to, so the JSON is cut out of whatever came back rather than trusted.
    private func decode<T: Decodable>(_ brain: Brain,
                                      system: String,
                                      user: String,
                                      temperature: Double) async -> T? {
        guard let raw = try? await brain.reply(system: system, user: user, temperature: temperature, json: true)
        else { return nil }
        guard let json = raw.firstJSONObject else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - Results

struct ProfileDraft {
    var name = ""
    var place = ""
    var summary = ""
    var whereMet = ""
    var facts: [String] = []
    var nextSteps: [String] = []
    var category = ""
}

struct SearchHit {
    var id: Int
    var line: String
}

/// What the address book gives us, before anything is made of it.
struct ContactSeed {
    var name = ""
    var org = ""
    var role = ""
    var city = ""
}

struct ContactDraft {
    var name = ""
    var category = ""
    var summary = ""
    var place = ""
    var facts: [String] = []
}

// MARK: - Wire shapes
//
// Every field optional: a model that omits a key should cost one empty section,
// not the whole decode.

private struct RemoteProfile: Decodable {
    var name: String?
    var place: String?
    var category: String?
    var summary: String?
    var whereMet: String?
    var facts: [String]?
    var nextSteps: [String]?
}

private struct RemoteAnswer: Decodable {
    struct Hit: Decodable { var id: Int?; var line: String? }
    var hits: [Hit]?
}

private struct RemoteBrief: Decodable {
    var lines: [String]?
}

private struct RemoteCards: Decodable {
    struct Card: Decodable {
        var i: Int?
        var category: String?
        var summary: String?
        var place: String?
        var facts: [String]?
    }
    var cards: [Card]?
}

private struct RemoteFiling: Decodable {
    struct Row: Decodable { var id: Int?; var category: String? }
    var filed: [Row]?
}

// MARK: -

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var strippedFence: String {
        guard let open = range(of: "```") else { return self }
        let afterOpen = self[open.upperBound...]
        // ```json\n{…}\n```
        let body = afterOpen.drop { $0 != "\n" }
        guard let close = body.range(of: "```") else { return String(body).trimmed }
        return String(body[body.startIndex..<close.lowerBound]).trimmed
    }

    /// The outermost balanced `{…}`, so trailing chatter after the object is
    /// dropped along with anything before it.
    var firstJSONObject: String? {
        let s = strippedFence
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(s[start...i]) }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }
}

private extension Array where Element == String {
    /// Models pad lists with empties and repeat themselves; neither reaches a card.
    var cleaned: [String] {
        var seen = Set<String>()
        return compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { return nil }
            return t
        }
    }
}

extension String {
    /// `@AI what should I ask her about?` → the question, or `nil` when the line
    /// is an ordinary one.
    ///
    /// Case-insensitive, because nobody holds shift twice mid-sentence, and
    /// `@IA` counts too: that is the acronym in French, and a French user typing
    /// it into a French note should not have to know the app was written in
    /// English.
    var aiQuestion: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 3 else { return nil }
        let head = t.prefix(3).lowercased()
        guard head == "@ai" || head == "@ia" else { return nil }

        let tail = t.dropFirst(3)
        // the prefix has to be a whole word: "@aixmarseille" is a handle
        // somebody typed, not a question, and answering it would be baffling
        guard let next = tail.first, !next.isLetter, !next.isNumber else { return nil }

        let rest = tail.drop { $0 == ":" || $0 == "," }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

extension String {
    /// Whether this name is really the front of a sentence the old parser sliced.
    ///
    /// Four words or more, or a lowercase word after the first — "J'ai rencontré
    /// jean chauvin" trips both. It also trips on "Ana de Armas", which costs one
    /// re-read that confirms the name and changes nothing.
    var readsLikeASentence: Bool {
        let words = split(separator: " ")
        guard words.count > 1 else { return false }
        return words.count > 3 || words.dropFirst().contains { $0.first?.isLowercase == true }
    }
}

extension Person {
    /// One line per person, numbered so a model can point back at an id.
    ///
    /// The meeting date carries its year here even though `meta` shows it without
    /// one. "Moving in the autumn" is only resolvable against the year the note
    /// was written, and the card's own subtitle is too terse to say.
    var dossier: String {
        let body = ([summary] + sections.flatMap(\.lines))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(240)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return "[\(id)] \(name) — met \(f.string(from: date)) — \(meta) — \(body)"
    }
}
