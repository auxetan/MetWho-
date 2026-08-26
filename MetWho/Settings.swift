import SwiftUI
import StoreKit

/// ScreenFast's pattern for a settings sub-page: a header card carrying the
/// icon, the title, and a plain-language description of what the thing does.
/// That description is not help text — it is the only place the feature is ever
/// explained, which is why it says what the app will *not* do as often as what
/// it will.
extension Bundle {
    /// Read rather than typed: the string was hard-coded in two places and would
    /// have gone stale the first time the build number moved.
    var versionLine: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

struct PageCard: View {
    let icon: String, title: String, desc: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon).font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.surface)
                .frame(width: 56, height: 56)
                .background(Color.ink2, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(title).font(.system(size: 22, weight: .heavy)).tracking(-0.66)
                .foregroundStyle(Color.ink).padding(.top, 16)
            Text(desc).bodyText().padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 20)
        .card()
    }
}

struct SubPage<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "chevron.left") { dismiss() }
                    Spacer()
                    Text(title).navTitle()
                    Spacer()
                    if let trailing { trailing } else { Color.clear.frame(width: M.circle, height: M.circle) }
                }
                .padding(.horizontal, M.gutter).padding(.top, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { content; Color.clear.frame(height: 50) }
                        .padding(.horizontal, M.gutter).padding(.top, 26)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Settings index

struct SettingsScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var shop = Purchases.shared
    @Binding var path: [Route]
    @State private var showCategories = false
    @State private var showFeedback = false

    var body: some View {
        @Bindable var store = store
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dismiss() }
                    Spacer()
                    Text("Settings").navTitle()
                    Spacer()
                    Color.clear.frame(width: M.circle, height: M.circle)
                }
                .padding(.horizontal, M.gutter).padding(.top, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        proBlock.padding(.top, 26)

                        SectionLabel(text: "General").padding(.top, 30)
                        Grouped {
                            HStack(spacing: 14) {
                                Image(systemName: "person.fill").font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color.ink).frame(width: 22)
                                Text("Your name").rowLabel()
                                Spacer(minLength: 8)
                                TextField("Optional", text: $store.prefs.name)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 17, weight: .bold)).tracking(-0.42)
                                    .foregroundStyle(Color.ink2)
                                    .onSubmit { store.save() }
                            }
                            .padding(.leading, 24).padding(.trailing, 20)
                            .frame(minHeight: M.hRow)
                            Hairline()
                            SettingsRow(icon: "bell.fill", label: "Notifications",
                                        value: store.prefs.notifications ? "On" : "Off") { path.append(.notifications) }
                            Hairline()
                            SettingsRow(icon: "archivebox.fill", label: "Archived",
                                        value: "\(store.archived.count)") { path.append(.archivedList) }
                            Hairline()
                            SettingsRow(icon: "arrow.up.arrow.down", label: "Default sort",
                                        value: store.prefs.sort.label) { path.append(.sortMode) }
                            Hairline()
                            SettingsRow(icon: "icloud.fill", label: "iCloud Sync",
                                        value: store.prefs.icloud ? "On" : "Off") { path.append(.icloud) }
                            Hairline()
                            SettingsRow(icon: "person.crop.rectangle.stack.fill", label: "Sync with Contacts") {
                                path.append(.contacts)
                            }
                        }

                        SectionLabel(text: "Customize").padding(.top, 30)
                        Grouped {
                            SettingsRow(icon: "circle.lefthalf.filled", label: "Appearance",
                                        value: store.prefs.theme.label) { path.append(.appearance) }
                            Hairline()
                            SettingsRow(icon: "tag.fill", label: "Categories",
                                        value: "\(store.categories.count)") { showCategories = true }
                            Hairline()
                            SettingsRow(icon: "square.grid.2x2.fill", label: "Widget") { path.append(.widget) }
                            Hairline(leading: 20)
                            SettingsRow(icon: "mic.fill", label: "Dictation",
                                        value: store.prefs.dictation.isEmpty ? nil
                                             : Locale.current.localizedString(forIdentifier: store.prefs.dictation)) {
                                path.append(.dictation)
                            }
                            Hairline()
                            SettingsRow(icon: "wand.and.stars.inverse", label: "Intelligence",
                                        value: AIConfig.shared.hasKey ? "On" : nil) { path.append(.intelligence) }
                        }

                        SectionLabel(text: "Support").padding(.top, 30)
                        Grouped {
                            SettingsRow(icon: "bubble.left.fill", label: "Give Feedback") { showFeedback = true }
                            Hairline()
                            SettingsRow(icon: "star.fill", label: "Rate MetWho") { requestReview() }
                            Hairline()
                            SettingsRow(icon: "info.circle.fill", label: "About MetWho") { path.append(.about) }
                        }

                        Grouped {
                            SettingsRow(icon: "wand.and.rays", label: "Load sample people",
                                        sub: "Six invented people, to look around with") {
                                withAnimation(.smooth) { store.loadSamples() }
                            }
                            Hairline()
                            SettingsRow(icon: "trash.fill", label: "Erase everything",
                                        sub: "Back to an empty app") {
                                withAnimation(.smooth) { store.reset() }
                            }
                        }
                        .padding(.top, 30)

                        VStack(spacing: 0) {
                            AppMark(size: 64)
                            Text("MetWho").font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Color.ink).padding(.top, 10)
                            Text(Bundle.main.versionLine).metaText().padding(.top, 2)
                            Text("Never forget a name again.").metaText().italic().padding(.top, 14)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 34)

                        Color.clear.frame(height: 50)
                    }
                    .padding(.horizontal, M.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCategories) {
            CategorySheet(mode: .filter) { _ in }
                .presentationDetents([.medium, .large]).presentationCornerRadius(34)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet().presentationDetents([.height(360)]).presentationCornerRadius(34)
        }
    }

    @ViewBuilder
    private var proBlock: some View {
        if shop.isPro {
            Button { path.append(.paywall) } label: {
                HStack(spacing: 12) {
                    Text("MetWho").font(.system(size: 20, weight: .heavy)).tracking(-0.6)
                        .foregroundStyle(Color.ink)
                    ProBadge()
                    Spacer()
                    Text("Lifetime").metaText()
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .card()
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("MetWho").font(.system(size: 22, weight: .heavy)).tracking(-0.66)
                        .foregroundStyle(Color.ink)
                    ProBadge()
                }
                VStack(alignment: .leading, spacing: 0) {
                    feature("person.2.fill", "Unlimited people")
                    feature("square.grid.2x2.fill", "Widgets")
                    feature("sparkles", "Sharper refreshers")
                }
                .padding(.top, 14)
                CTA(title: "Try for free", inCard: true) { path.append(.paywall) }
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func feature(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 19, weight: .bold)).foregroundStyle(Color.ink)
                .frame(width: 23)
            Text(label).font(.system(size: 17.5, weight: .heavy)).tracking(-0.52).foregroundStyle(Color.ink)
        }
        .frame(minHeight: 46)
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO").font(.system(size: 15, weight: .heavy)).tracking(-0.15)
            .foregroundStyle(Color.ctaFG)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Color.ctaBG, in: Capsule(style: .continuous))
    }
}

/// The app mark, drawn rather than bitmapped so it stays crisp at every size:
/// a black card with a ribbon tab, and two people filed into it.
struct AppMark: View {
    var size: CGFloat = 112
    var body: some View {
        let card = size * 0.615
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
            ZStack {
                RoundedRectangle(cornerRadius: card * 0.245, style: .continuous)
                    .fill(Color(white: 0.055))
                Ribbon()
                    .fill(Color(white: 0.96))
                    .frame(width: card * 0.195, height: card * 0.235)
                    .offset(y: -card * 0.383)
                People()
                    .frame(width: card * 0.72, height: card * 0.46)
                    .offset(y: card * 0.10)
            }
            .frame(width: card, height: card)
            .offset(y: size * 0.012)
        }
        .frame(width: size, height: size)
    }
}

private struct Ribbon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let notch = r.height * 0.30
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - notch))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct People: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // the figure behind, dimmed so the overlap reads
                Circle().fill(.white)
                    .frame(width: w * 0.26, height: w * 0.26)
                    .position(x: w * 0.70, y: h * 0.20)
                Shoulders().fill(Color(white: 0.86))
                    .frame(width: w * 0.47, height: h * 0.48)
                    .position(x: w * 0.70, y: h * 0.76)
                Circle().fill(.white)
                    .frame(width: w * 0.31, height: w * 0.31)
                    .position(x: w * 0.34, y: h * 0.17)
                Shoulders().fill(.white)
                    .frame(width: w * 0.55, height: h * 0.56)
                    .position(x: w * 0.34, y: h * 0.72)
            }
        }
    }
}

private struct Shoulders: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = r.width / 2
        let corner = r.width * 0.12
        p.move(to: CGPoint(x: r.minX, y: r.maxY - corner))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        p.addQuadCurve(to: CGPoint(x: r.maxX - corner, y: r.maxY),
                       control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + corner, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - corner),
                       control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Sub-pages

struct NotificationsPage: View {
    @Environment(Store.self) private var store
    @State private var denied = false

    /// Turning the row on is also where permission is asked for. A separate
    /// "allow notifications" step before the switch that does the thing is one
    /// screen nobody needs.
    private func toggle() async {
        if store.prefs.notifications {
            store.prefs.notifications = false
            Nudges.cancelAll()
        } else {
            guard await Nudges.authorize() else { denied = true; return }
            denied = false
            store.prefs.notifications = true
            await Nudges.reschedule(for: store.people)
        }
        store.save()
    }

    var body: some View {
        @Bindable var store = store
        SubPage(title: "Notifications") {
            PageCard(icon: "bell.fill", title: "Notifications",
                     desc: "One nudge, about the person you have gone longest without seeing. Never a digest, never a streak, never a reason to open the app that MetWho invented for you.")
            SectionLabel(text: "Nudges").padding(.top, 30)
            Grouped {
                SettingsRow(icon: "sparkles", label: "Someone you have not seen",
                            value: denied ? "Blocked in Settings" : (store.prefs.notifications ? "Weekly" : "Off"),
                            accessory: store.prefs.notifications && !denied ? .check : .none) {
                    Task { await toggle() }
                }
            }
            Text(denied
                 ? "iOS is blocking notifications for MetWho. Turn them on in Settings → MetWho → Notifications."
                 : "Scheduled on this device from the dates in your own notes. Nothing leaves the phone.")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink2)
                .padding(.horizontal, 22).padding(.top, 9)
        }
    }
}

struct ArchivedPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        SubPage(title: "Archived") {
            PageCard(icon: "archivebox.fill", title: "Archived",
                     desc: "People you have put away. They stay searchable and keep their memories — they just leave the feed.")
            SectionLabel(text: "\(store.archived.count) \(store.archived.count == 1 ? "person" : "people")")
                .padding(.top, 30)
            Grouped {
                if store.archived.isEmpty {
                    Text("Nothing archived.").snipText().frame(maxWidth: .infinity).padding(.vertical, 34)
                }
                ForEach(Array(store.archived.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Hairline(leading: 20) }
                    HStack(spacing: 14) {
                        Avatar(person: p, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                            Text(p.meta).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink2)
                        }
                        Spacer(minLength: 8)
                        Chip(title: "Restore", icon: "arrow.up.bin.fill") {
                            withAnimation(.smooth) { store.restore(p.id) }
                        }
                    }
                    .padding(.horizontal, 20).frame(minHeight: M.hRow)
                }
            }
        }
    }
}

struct SortPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        SubPage(title: "Default sort") {
            PageCard(icon: "arrow.up.arrow.down", title: "Default sort",
                     desc: "How the feed is ordered. Manual keeps whatever order you dragged the gallery into.")
            SectionLabel(text: "Order").padding(.top, 30)
            Grouped {
                ForEach(Array(SortMode.allCases.enumerated()), id: \.element) { i, mode in
                    if i > 0 { Hairline(leading: 20) }
                    SettingsRow(label: mode.label,
                                sub: mode == .manual ? "Drag to reorder in the gallery" : nil,
                                accessory: store.prefs.sort == mode ? .check : .none) {
                        withAnimation(.smooth) { store.prefs.sort = mode }; store.save()
                    }
                }
            }
        }
    }
}

struct CloudPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        SubPage(title: "iCloud Sync") {
            PageCard(icon: "icloud.fill", title: "iCloud Sync",
                     desc: "Your people on every device signed into the same Apple Account. It goes through your own iCloud, never through a MetWho server — there isn't one.")
            SectionLabel(text: "Sync").padding(.top, 30)
            Grouped {
                SettingsRow(icon: "icloud.fill", label: "iCloud Sync",
                            value: CloudSync.isAvailable ? (store.prefs.icloud ? "On" : "Off") : "Not signed in",
                            accessory: store.prefs.icloud && CloudSync.isAvailable ? .check : .none) {
                    guard CloudSync.isAvailable else { return }
                    store.prefs.icloud.toggle(); store.save()
                }
            }
            Text(CloudSync.isAvailable
                 ? "\(store.people.count) people. Photos stay on the device that added them — iCloud's key-value store is capped at 1 MB, so only the words travel."
                 : "Sign in to iCloud on this device to turn sync on.")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink2)
                .padding(.horizontal, 22).padding(.top, 9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ContactsPage: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var access: PhoneContacts.Access?
    @State private var seeds: [ContactSeed] = []
    @State private var picked: Set<String> = []
    @State private var importing = false

    /// Everyone already in MetWho is dropped from the list: the second import of
    /// the same person is never what anyone meant.
    private var fresh: [ContactSeed] {
        let known = Set(store.people.map { $0.name.lowercased() })
        return seeds.filter { !known.contains($0.name.lowercased()) }
    }

    var body: some View {
        SubPage(title: "Sync with Contacts",
                trailing: picked.isEmpty ? nil
                    : AnyView(Chip(title: importing ? "Importing" : "Import \(picked.count)",
                                   solid: true, action: importPicked))) {
            PageCard(icon: "person.crop.rectangle.stack.fill", title: "Sync with Contacts",
                     desc: "Pick the people you already keep in Contacts. MetWho copies the name, employer and city — no numbers, no addresses — and never writes back.")

            switch access {
            case nil:
                Text("Reading your contacts…").snipText().padding(.top, 50)
            case .denied:
                Text("MetWho has no access to Contacts. Turn it on in Settings → MetWho → Contacts.")
                    .snipText().multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 50)
            case .restricted:
                Text("Contacts are restricted on this device.")
                    .snipText().padding(.top, 50)
            case .granted where fresh.isEmpty:
                Text(seeds.isEmpty ? "No contacts on this phone."
                                   : "Everyone in your address book is already here.")
                    .snipText().multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 50)
            case .granted:
                SectionLabel(text: "\(fresh.count) not in MetWho yet").padding(.top, 30)
                Grouped {
                    ForEach(Array(fresh.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Hairline(leading: 20) }
                        row(s)
                    }
                }
                Text("Names, employer and city only. What they do gets written up when you import.")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink2)
                    .padding(.horizontal, 22).padding(.top, 9)
            }
        }
        .task {
            let granted = await PhoneContacts.request()
            access = granted
            guard granted == .granted else { return }
            seeds = await Task.detached(priority: .userInitiated) { PhoneContacts.fetch() }.value
        }
    }

    private func row(_ s: ContactSeed) -> some View {
        Button {
            if picked.contains(s.name) { picked.remove(s.name) } else { picked.insert(s.name) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.avatarBG)
                    Text(String(s.name.prefix(1))).font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.ink)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                    let detail = [s.role, s.org, s.city].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(picked.contains(s.name) ? Color.ink : Color.clear)
                    Circle().strokeBorder(picked.contains(s.name) ? Color.ink : Color.ink3, lineWidth: 2.2)
                    if picked.contains(s.name) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.bg)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 20).frame(minHeight: M.hRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func importPicked() {
        guard !importing else { return }
        importing = true
        let chosen = fresh.filter { picked.contains($0.name) }
        Task {
            await store.importContacts(chosen)
            dismiss()
        }
    }
}

struct AppearancePage: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        SubPage(title: "Appearance") {
            PageCard(icon: "circle.lefthalf.filled", title: "Appearance",
                     desc: "MetWho is black and white in both modes. Dark drops every shadow and carries elevation with value alone.")
            SectionLabel(text: "Theme").padding(.top, 30)
            Grouped {
                ForEach(Array(ThemeMode.allCases.enumerated()), id: \.element) { i, mode in
                    if i > 0 { Hairline(leading: 20) }
                    SettingsRow(label: mode.label,
                                accessory: store.prefs.theme == mode ? .check : .none) {
                        withAnimation(.smooth) { store.prefs.theme = mode }; store.save()
                    }
                }
            }
        }
    }
}

/// The one screen where the intelligence is admitted to exist.
///
/// Everywhere else it is meant to be invisible; here it needs a key, and a key
/// needs somewhere to be typed. The field is a `SecureField` and the value goes
/// to the keychain, never to the notes file.
struct IntelligencePage: View {
    @State private var config = AIConfig.shared
    @State private var revealed = false

    var body: some View {
        SubPage(title: "Intelligence") {
            PageCard(icon: "wand.and.stars.inverse", title: "Intelligence",
                     desc: "Reads your notes into proper profiles, sorts them, and answers plain questions in the search box. Paste an OpenAI or Cerebras key — MetWho works out which from the key itself. Without one it uses Apple's on-device model when the phone has it.")

            SectionLabel(text: config.hasKey ? config.provider.label : "OpenAI or Cerebras").padding(.top, 30)
            Grouped {
                HStack(spacing: 14) {
                    Image(systemName: "key.fill").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink).frame(width: 22)
                    Group {
                        if revealed {
                            TextField("API key", text: $config.key)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("API key", text: $config.key)
                        }
                    }
                    .font(.system(size: 17, weight: .bold)).tracking(-0.42)
                    .foregroundStyle(Color.ink)
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 24).padding(.trailing, 20)
                .frame(minHeight: M.hRow)

                Hairline(leading: 20)
                HStack(spacing: 14) {
                    Image(systemName: "cpu.fill").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink).frame(width: 22)
                    TextField(config.provider.defaultModel, text: $config.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 17, weight: .bold)).tracking(-0.42)
                        .foregroundStyle(Color.ink)
                }
                .padding(.leading, 24).padding(.trailing, 20)
                .frame(minHeight: M.hRow)

                Hairline(leading: 20)
                SettingsRow(icon: "bolt.fill", label: "Status",
                            value: config.status, accessory: .none)
            }

            Text("The key is stored in the iOS keychain. Your notes are sent to \(config.hasKey ? config.provider.label : "the service") only when it has work to do, and stay on the phone otherwise.")
                .snipText().padding(.horizontal, 4).padding(.top, 14)

            SectionLabel(text: "In a note").padding(.top, 30)
            Grouped {
                SettingsRow(icon: "at", label: "@AI",
                            sub: "Type @AI followed by a question on its own line, press return, and the answer replaces it.",
                            accessory: .none)
            }
        }
    }
}

/// Which language Dictate listens for.
///
/// `SFSpeechRecognizer` needs the language up front — it cannot work out what it
/// is hearing — so this is a choice rather than something detected. Following
/// the phone is right until someone keeps notes in a language they never set it
/// to, which is exactly the case this page exists for.
struct DictationPage: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        SubPage(title: "Dictation") {
            PageCard(icon: "mic.fill", title: "Dictation",
                     desc: "Text appears on this iPhone as you talk. With a key connected the recording is also read once by OpenAI, which hears names better and works out the language itself, then deleted. When you correct yourself out loud, the correction is kept and the mistake dropped.")

            SectionLabel(text: "Language").padding(.top, 30)
            Grouped {
                SettingsRow(label: "Follow this iPhone",
                            sub: Locale.current.localizedString(forIdentifier: Locale.current.identifier),
                            accessory: store.prefs.dictation.isEmpty ? .check : .none) {
                    store.prefs.dictation = ""; store.save()
                }
                ForEach(Dictation.available, id: \.id) { lang in
                    Hairline(leading: 20)
                    SettingsRow(label: lang.name,
                                accessory: store.prefs.dictation == lang.id ? .check : .none) {
                        store.prefs.dictation = lang.id; store.save()
                    }
                }
            }
            Text(AIConfig.shared.hasKey && AIConfig.shared.provider == .openAI
                 ? "Only used when the recording cannot be sent. OpenAI works the language out on its own."
                 : "Takes effect the next time you open a note.")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink2)
                .padding(.horizontal, 22).padding(.top, 9)
        }
    }
}

struct WidgetPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        SubPage(title: "Widget") {
            PageCard(icon: "square.grid.2x2.fill", title: "Widget",
                     desc: "Today’s people on your Home Screen. Tap one to open straight into their refresher.")
            SectionLabel(text: "Preview").padding(.top, 30)
            VStack(alignment: .leading, spacing: 12) {
                Text("Medium").metaText()
                HStack(spacing: 10) {
                    ForEach(store.feed.prefix(3)) { p in
                        VStack(spacing: 7) {
                            Avatar(person: p, size: 40)
                            Text(p.name.split(separator: " ").first.map(String.init) ?? p.name)
                                .metaText().foregroundStyle(Color.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }
}

struct AboutPage: View {
    @State private var legal: String?
    var body: some View {
        SubPage(title: "About") {
            VStack(spacing: 0) {
                AppMark()
                Text("MetWho").font(.system(size: 21, weight: .heavy)).tracking(-0.6)
                    .foregroundStyle(Color.ink).padding(.top, 16)
                Text(Bundle.main.versionLine).metaText().padding(.top, 3)
            }
            .frame(maxWidth: .infinity).padding(.top, 20)

            Text("MetWho is named for the question you ask yourself three seconds too late.\n\nSay what you want to remember once. It becomes a profile you can search in plain words, and a ten-second refresher before you see that person again.")
                .font(.tBody).foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .padding(.top, 28)

            Grouped {
                SettingsRow(icon: "doc.text.fill", label: "Terms of Service") { legal = "terms" }
                Hairline()
                SettingsRow(icon: "lock.fill", label: "Privacy Policy") { legal = "privacy" }
            }
            .padding(.top, 30)
        }
        .sheet(item: Binding(get: { legal.map(LegalKind.init) }, set: { legal = $0?.id })) { kind in
            LegalSheet(kind: kind).presentationCornerRadius(34)
        }
    }
}

struct LegalKind: Identifiable { let id: String; init(_ id: String) { self.id = id } }

struct LegalSheet: View {
    let kind: LegalKind
    @Environment(\.dismiss) private var dismiss

    private var title: String { kind.id == "terms" ? "Terms of Service" : "Privacy Policy" }
    private var body_: [(String, String)] {
        kind.id == "terms"
        ? [("1. What this is", "MetWho stores what you choose to write down about people you meet. It is a notebook, not a directory."),
           ("2. Your data", "Everything lives on your device. If iCloud Sync is on, it is end-to-end encrypted and unreadable by us."),
           ("3. What you put in", "You are responsible for what you record about other people, and for having a reason to record it."),
           ("4. Subscription", "PRO renews until cancelled. Cancel any time in the App Store; the current period is not refunded."),
           ("5. Ending it", "Delete the app and every local copy goes with it.")]
        : [("What leaves your phone", "Nothing, unless iCloud Sync is on — and then it is encrypted before it leaves."),
           ("Contacts", "If you import from Contacts, MetWho copies names only. No numbers, no addresses, and it never writes back."),
           ("Calendar", "Read on device to rank suggestions and time a nudge. Event contents are never stored or sent."),
           ("Photos", "Photos you attach stay in the app's own storage."),
           ("Analytics", "None. No SDK, no identifier, no crash reporter.")]
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dismiss() }
                    Spacer(); Text(title).navTitle(); Spacer()
                    Color.clear.frame(width: M.circle, height: M.circle)
                }
                .padding(.horizontal, M.gutter).padding(.top, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(body_.enumerated()), id: \.offset) { _, item in
                            Text(item.0).font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                                .padding(.top, 18)
                            Text(item.1).snipText().padding(.top, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .card()
                    .padding(.horizontal, M.gutter).padding(.top, 20)
                    Text("Last updated 23 August 2026").metaText().padding(.top, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Give feedback")
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What is missing, what is in the way?")
                            .font(.tBody).foregroundStyle(Color.ink3).padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: $text).font(.tBody).foregroundStyle(Color.ink)
                        .scrollContentBackground(.hidden).focused($focused).frame(height: 120)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
                CTA(title: "Send") { dismiss() }.padding(.top, 14)
            }
            .padding(.horizontal, M.gutter).padding(.top, 22)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Paywall

struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shop = Purchases.shared
    @State private var chosen: Product?

    private let features = [("person.2.fill", "Unlimited people", "The free tier keeps your last 20."),
                            ("sparkles", "Sharper refreshers", "Longer memories, better summaries before you meet."),
                            ("square.grid.2x2.fill", "Widgets", "Today’s people on your Home Screen."),
                            ("tag.fill", "Unlimited categories", "Past the three you get for free."),
                            ("icloud.fill", "iCloud Sync", "Every device, end-to-end encrypted.")]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dismiss() }
                    Spacer()
                    Chip(title: "Restore") { Task { await shop.restore() } }
                }
                .padding(.horizontal, M.gutter).padding(.top, 6)

                ScrollView {
                    VStack(spacing: 0) {
                        AppMark().padding(.top, 16)
                        HStack(spacing: 11) {
                            Text("MetWho").font(.system(size: 28, weight: .heavy)).tracking(-0.95)
                                .foregroundStyle(Color.ink)
                            ProBadge()
                        }
                        .padding(.top, 18)
                        Text("Remember everyone you meet, not just the last twenty.")
                            .snipText().multilineTextAlignment(.center).frame(maxWidth: 290).padding(.top, 8)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(features.enumerated()), id: \.offset) { _, f in
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: f.0).font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(Color.ink).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.1).font(.system(size: 17, weight: .heavy)).tracking(-0.5)
                                            .foregroundStyle(Color.ink)
                                        Text(f.2).font(.system(size: 14.5, weight: .semibold))
                                            .foregroundStyle(Color.ink2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 11)
                            }
                        }
                        .padding(.top, 20)
                        Color.clear.frame(height: 320)
                    }
                    .padding(.horizontal, M.gutter)
                }
                .scrollIndicators(.hidden)
            }

            VStack(spacing: 9) {
                if shop.products.isEmpty {
                    Text("Subscriptions are not available right now.")
                        .snipText().multilineTextAlignment(.center).padding(.vertical, 18)
                } else {
                    ForEach(shop.products, id: \.id) { product in
                        planRow(product)
                    }
                    if let failure = shop.failure {
                        Text(failure).snipText().multilineTextAlignment(.center).padding(.top, 2)
                    }
                    CTA(title: shop.busy ? "One moment" : "Continue") {
                        guard let product = chosen ?? shop.products.first else { return }
                        Task {
                            await shop.buy(product)
                            if shop.isPro { dismiss() }
                        }
                    }
                    .padding(.top, 3)
                    .disabled(shop.busy)
                }
                HStack(spacing: 18) {
                    Link("Terms & Conditions", destination: Self.terms)
                    Link("Privacy Policy", destination: Self.privacy)
                }
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.ink2)
                .padding(.top, 4)
            }
            .padding(.horizontal, M.gutter).padding(.top, 20).padding(.bottom, 8)
            .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 24, y: -10)
        }
        .navigationBarHidden(true)
        .task {
            await shop.load()
            if shop.isPro { dismiss() }
            // the longer plan is the one worth defaulting to, and it sorts last
            chosen = chosen ?? shop.products.last
        }
    }

    /// Apple requires the price, the period and the terms to come from StoreKit
    /// and be shown before the buy button. Nothing here is a literal.
    private func planRow(_ product: Product) -> some View {
        let picked = chosen?.id == product.id
        return Button { withAnimation(.snappy) { chosen = product } } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(picked ? Color.ink : Color.clear)
                    Circle().strokeBorder(picked ? Color.ink : Color.ink3, lineWidth: 2.2)
                    if picked {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.bg)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.displayName).font(.system(size: 17, weight: .heavy)).tracking(-0.5)
                        .foregroundStyle(Color.ink)
                    if let offer = product.subscription?.introductoryOffer {
                        Text(introLine(offer)).font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                    }
                }
                Spacer(minLength: 8)
                Text(product.priceLine).font(.system(size: 17, weight: .heavy)).tracking(-0.54)
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .background(picked ? Color.bg : Color.fillSoft,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(picked ? Color.ink : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func introLine(_ offer: Product.SubscriptionOffer) -> String {
        let n = offer.period.value
        let unit = switch offer.period.unit {
        case .day: n == 1 ? "day" : "days"
        case .week: n == 1 ? "week" : "weeks"
        case .month: n == 1 ? "month" : "months"
        case .year: n == 1 ? "year" : "years"
        @unknown default: "days"
        }
        return offer.paymentMode == .freeTrial ? "\(n) \(unit) free" : "\(offer.displayPrice) for \(n) \(unit)"
    }

    private static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacy = URL(string: "https://metwho.app/privacy")!
}
