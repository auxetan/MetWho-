import SwiftUI

@main
struct MetWhoApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(store.prefs.theme.scheme)
                .tint(.ink)
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    var body: some View {
        ZStack {
            HomeScreen()
            if !store.prefs.onboarded {
                OnboardingView().transition(.opacity)
            }
        }
        // after onboarding only: filing the demo seed on a first run would move
        // people the user has not even met yet
        .task {
            Dictation.preferred = store.prefs.dictation
            await Purchases.shared.load()
            guard store.prefs.onboarded else { return }
            if store.prefs.notifications { await Nudges.reschedule(for: store.people) }
            await store.tidy()
        }
    }
}

@ViewBuilder
func destination(_ route: Route, path: Binding<[Route]>, toast: Binding<ToastState?>) -> some View {
    switch route {
    case .profile(let id):  ProfileScreen(personID: id, toast: toast)
    case .search:           SearchScreen { id in path.wrappedValue.append(.profile(id)) }
    case .settings:         SettingsScreen(path: path)
    case .notifications:    NotificationsPage()
    case .archivedList:     ArchivedPage()
    case .sortMode:         SortPage()
    case .icloud:           CloudPage()
    case .contacts:         ContactsPage()
    case .appearance:       AppearancePage()
    case .widget:           WidgetPage()
    case .intelligence:     IntelligencePage()
    case .dictation:        DictationPage()
    case .about:            AboutPage()
    case .paywall:          PaywallScreen()
    }
}

// MARK: - Onboarding
// Cards 2 and 3 play the actual interaction on a loop. Describing a feature in
// a subtitle is weaker than letting someone watch it happen.

struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var page = 0

    private let copy: [(title: String, sub: String, cta: String)] = [
        ("Welcome to MetWho", "Remembers the people you meet, so you don't have to.", "Get Started"),
        ("Say it once", "Dictate what you want to keep. MetWho writes the profile.", "Continue"),
        ("Ask in plain words", "Who works in fashion? Who did I meet at Devoxx?", "Continue"),
        ("Never walk in cold", "A ten-second refresher before you see someone again.", "Continue"),
        ("What should I call you?", "Only ever used to say good morning. It stays on this phone.", "Continue"),
        ("Three things to allow", "Each one is asked for a reason. MetWho works without any of them.", "Start remembering"),
    ]

    private var last: Int { copy.count - 1 }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if page > 0 {
                        CircleButton(icon: "chevron.left") { withAnimation(.smooth) { page -= 1 } }
                    } else {
                        Color.clear.frame(width: M.circle, height: M.circle)
                    }
                    Spacer()
                }
                .padding(.horizontal, M.gutter).padding(.top, 6)

                Group {
                    switch page {
                    case 0: AppMark()
                    case 1: DictationDemo()
                    case 2: SearchDemo()
                    case 3: RefresherDemo()
                    case 4: NameCard()
                    default: PermissionCard()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, M.gutter)

                VStack(spacing: 0) {
                    Text(copy[page].title)
                        .font(.system(size: 29, weight: .heavy)).tracking(-1.0)
                        .foregroundStyle(Color.ink).multilineTextAlignment(.center)
                    Text(copy[page].sub).snipText().multilineTextAlignment(.center)
                        .frame(maxWidth: 300).padding(.top, 9)
                    HStack(spacing: 8) {
                        ForEach(0..<copy.count, id: \.self) { i in
                            Capsule().fill(i == page ? Color.ink : Color.ink3)
                                .frame(width: i == page ? 22 : 6, height: 6)
                        }
                    }
                    .padding(.top, 26).padding(.bottom, 20)
                    CTA(title: copy[page].cta) {
                        if page == last {
                            withAnimation(.smooth) { store.prefs.onboarded = true }
                            store.save()
                        } else {
                            withAnimation(.smooth) { page += 1 }
                        }
                    }
                }
                .padding(.horizontal, M.gutterCTA).padding(.bottom, 10)
            }
        }
    }
}

/// The one field the app ever asks anyone to fill in.
///
/// The art direction says MetWho never puts a form in front of you, and that
/// still holds everywhere else — this is a greeting, not a profile, and skipping
/// it costs nothing: an empty name just means the home screen says "Good
/// morning" with nothing after it.
struct NameCard: View {
    @Environment(Store.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if store.prefs.name.isEmpty {
                    Text("Your first name")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink3)
                }
                TextField("", text: $store.prefs.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .onSubmit { store.save() }
            }
            .padding(.horizontal, 20).frame(height: 60)
            .floatCard()
        }
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .onDisappear { store.save() }
    }
}

/// Asked once, in a card, instead of three system alerts fired at launch.
///
/// Each row triggers the real request on tap and reports what the system
/// actually returned — a row that says "Allowed" means iOS said yes, never that
/// the app asked politely. Every one of the three is optional and the CTA
/// underneath never waits for them.
struct PermissionCard: View {
    @State private var mic: Bool?
    @State private var contacts: Bool?
    @State private var notifs: Bool?

    var body: some View {
        Grouped {
            row(icon: "mic.fill", label: "Microphone",
                sub: "So you can say it instead of typing it", state: mic) {
                if case .denied = await Dictation.authorize() { mic = false } else { mic = true }
            }
            Hairline(leading: 20)
            row(icon: "person.crop.rectangle.stack.fill", label: "Contacts",
                sub: "To pick who you already know", state: contacts) {
                contacts = await PhoneContacts.request() == .granted
            }
            Hairline(leading: 20)
            row(icon: "bell.fill", label: "Notifications",
                sub: "One nudge about someone you have not seen", state: notifs) {
                notifs = await Nudges.authorize()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(icon: String, label: String, sub: String, state: Bool?,
                     ask: @escaping () async -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.ink).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).rowLabel()
                Text(sub).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            switch state {
            case true:
                Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.ink)
            case false:
                Text("Denied").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink3)
            case nil:
                Chip(title: "Allow") { Task { await ask() } }
            }
        }
        .padding(.leading, 24).padding(.trailing, 20)
        .frame(minHeight: 74)
    }
}

/// The sentence types itself with an uneven rhythm — even timing reads as a
/// computer printing, uneven timing reads as someone talking.
struct DictationDemo: View {
    @State private var shown = ""
    @State private var caret = true
    private static let line = "Clara, met at Devoxx in the line for the Algolia stand. She's building a recipe app and looking for a product designer."

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 0) {
                Text(shown) + Text(caret ? "|" : " ").foregroundColor(.ink)
            }
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
            .padding(20)
            .floatCard()

            HStack(spacing: 11) {
                Circle().fill(Color.ink).frame(width: 15, height: 15)
                Text("Listening").font(.system(size: 17, weight: .heavy)).tracking(-0.42)
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 26).frame(height: M.circle)
            .glass()
        }
        .task {
            while !Task.isCancelled {
                shown = ""
                for ch in Self.line {
                    if Task.isCancelled { return }
                    shown.append(ch)
                    let pause: Duration = ch == "," || ch == "." ? .milliseconds(320)
                        : ch == " " ? .milliseconds(92) : .milliseconds(Int.random(in: 28...62))
                    try? await Task.sleep(for: pause)
                }
                try? await Task.sleep(for: .seconds(2.4))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                caret.toggle()
            }
        }
    }
}

/// A four-beat loop: the home sits there, a tap blooms on the search icon, the
/// push happens, the query types, the results rise in.
struct SearchDemo: View {
    @Environment(Store.self) private var store
    @State private var step = 0
    @State private var typed = ""
    @State private var tap = false

    private let hits = [("Hugo Trémaux", "has been at Jacquemus since January"),
                        ("Sofia Lindqvist", "styles shoots for Vogue Scandinavia")]

    var body: some View {
        ZStack {
            miniHome
                .offset(x: step >= 2 ? -90 : 0)
                .opacity(step >= 2 ? 0.16 : 1)
            searchPage
                .offset(x: step >= 2 ? 0 : 400)
                .opacity(step >= 2 ? 1 : 0)
        }
        .animation(.smooth, value: step)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task {
            while !Task.isCancelled {
                step = 0; typed = ""; tap = false
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeOut(duration: 0.5)) { tap = true }
                try? await Task.sleep(for: .milliseconds(420))
                tap = false; step = 2
                try? await Task.sleep(for: .milliseconds(480))
                for ch in "Who works in fashion?" {
                    if Task.isCancelled { return }
                    typed.append(ch)
                    try? await Task.sleep(for: .milliseconds(ch == " " ? 92 : 40))
                }
                step = 3
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private var miniHome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 14).frame(height: 38).glass()
                Spacer()
                HStack(spacing: 15) {
                    ForEach(["magnifyingglass", "square.grid.2x2.fill", "gearshape.fill"], id: \.self) { s in
                        Image(systemName: s).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
                    }
                }
                .padding(.horizontal, 13).frame(height: 38).glass()
                .overlay(alignment: .leading) {
                    Circle().fill(Color.ink.opacity(0.14))
                        .frame(width: 34, height: 34)
                        .scaleEffect(tap ? 1.5 : 0.4).opacity(tap ? 0 : 0.9)
                        .offset(x: 4)
                }
            }
            Text("Good morning,\n\(store.prefs.name)")
                .font(.system(size: 19, weight: .heavy)).tracking(-0.6)
                .foregroundStyle(Color.ink).padding(.top, 18)
            VStack(spacing: 8) {
                ForEach(store.people.dropFirst().prefix(2)) { p in
                    HStack(spacing: 11) {
                        Avatar(person: p, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(Color.ink)
                            Text(p.meta).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.ink2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }

    private var searchPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.5))
                Text(typed.isEmpty ? "Search" : typed)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(typed.isEmpty ? Color.ink3 : Color.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(height: 44).glass()

            if step >= 3 {
                VStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.offset) { i, h in
                        if i > 0 { Rectangle().fill(Color.hairline).frame(height: 1) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.0).font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                            Text("“\(h.1)”").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 0)
        }
        .background(Color.bg)
    }
}

struct RefresherDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clara Vasseur").cardTitle()
            Text("Building a recipe app, still looking for a product designer.\nYou owe her Léa’s contact.\nJust back from Lisbon.")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
            Text("Seen 2 months ago").metaText().padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .floatCard()
    }
}
