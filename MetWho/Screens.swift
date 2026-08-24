import SwiftUI
import PhotosUI

enum Route: Hashable {
    case profile(Int)
    case search, settings
    case notifications, archivedList, sortMode, icloud, contacts, appearance, widget, about, paywall
    case intelligence
}

// MARK: - Home

struct HomeScreen: View {
    @Environment(Store.self) private var store
    @State private var path: [Route] = []
    @State private var showCategories = false
    @State private var showCapture = false
    @State private var showArchive = false
    @State private var showPlaces = false
    @State private var toast: ToastState?

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case ..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color.bg.ignoresSafeArea()

                // the header is not stacked above the scroll view but laid over
                // it, so cards travel *behind* the glass instead of stopping at
                // its edge — the pills only read as floating if something can
                // pass under them
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                            Text(store.prefs.name.isEmpty ? greeting : "\(greeting),\n\(store.prefs.name)")
                                .display()
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, M.circle + 40)
                            Text(subtitle).snipText().padding(.top, 8)

                            if store.feed.isEmpty {
                                emptyState.padding(.top, 60)
                            } else if store.prefs.gallery {
                                gallery.padding(.top, 26)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(store.feed) { p in
                                        SwipeRow {
                                            path.append(.profile(p.id))
                                        } onArchive: {
                                            withAnimation(.smooth) { store.archive(p.id) }
                                            toast = ToastState(message: "Archived") {
                                                withAnimation(.smooth) { store.restore(p.id) }
                                            }
                                        } onDelete: {
                                            var removed: (Person, Int)?
                                            withAnimation(.smooth) { removed = store.delete(p.id) }
                                            guard let (gone, at) = removed else { return }
                                            toast = ToastState(message: "Deleted") {
                                                withAnimation(.smooth) { store.reinsert(gone, at: at) }
                                            }
                                        } content: {
                                            PersonCard(person: p)
                                        }
                                    }
                                }
                                .padding(.top, 26)
                            }
                            Color.clear.frame(height: 150)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, M.gutter)
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 0) { header; Spacer(minLength: 0) }

                BottomFade()
                if store.selecting { selectionBar } else { floatingButtons }
                if let toast { ToastView(state: toast) { self.toast = nil } }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                destination(route, path: $path, toast: $toast)
            }
        }
        .sheet(isPresented: $showCategories) {
            CategorySheet(mode: .filter) { toast = $0 }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet { created in
                if let created { path.append(.profile(created)) }
            }
        }
        .sheet(isPresented: $showArchive) {
            ArchiveSheet().presentationDetents([.medium]).presentationCornerRadius(34)
        }
        .sheet(isPresented: $showPlaces) {
            PlacesSheet { id in showPlaces = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(.profile(id)) } }
                .presentationDetents([.medium, .large]).presentationCornerRadius(34)
        }
    }

    private var subtitle: String {
        let n = store.feed.count
        return n == 0 ? "No one yet." : "\(n) \(n == 1 ? "person" : "people") you've met"
    }

    /// The first thing anyone sees on a fresh install, now that one no longer
    /// arrives pre-filled with invented people.
    private var emptyState: some View {
        VStack(spacing: 10) {
            AppMark(size: 62)
            Text(store.prefs.cat == "all" ? "Nobody in here yet" : "Nothing under \(store.label(store.prefs.cat))")
                .font(.system(size: 19, weight: .heavy)).tracking(-0.6)
                .foregroundStyle(Color.ink).padding(.top, 4)
            Text("Tap + after you meet someone and say what you want to remember. MetWho writes the profile.")
                .snipText().multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            HeaderPillSelect(label: store.label(store.prefs.cat)) { showCategories = true }
            Spacer()
            HeaderPillGroup(icons: ["magnifyingglass",
                                    store.prefs.gallery ? "list.bullet" : "square.grid.2x2.fill",
                                    "gearshape.fill"]) { i in
                switch i {
                case 0: path.append(.search)
                case 1: withAnimation(.smooth) { store.prefs.gallery.toggle() }; store.save()
                default: path.append(.settings)
                }
            }
        }
        .padding(.horizontal, M.gutter).padding(.top, 6)
    }

    private var gallery: some View {
        VStack(spacing: 11) {
            Button { showPlaces = true } label: {
                GlobeView(places: Array(Set(store.people.filter { !$0.archived }.map(\.place))))
                    .overlay(alignment: .bottomLeading) {
                        (Text("\(store.placesByCity.count) places").foregroundStyle(.white)
                         + Text(" · " + store.placesByCity.prefix(4).map(\.city).joined(separator: ", "))
                            .foregroundStyle(.white.opacity(0.62)))
                        .font(.system(size: 13, weight: .heavy)).tracking(-0.26)
                        .padding(.horizontal, 18).padding(.bottom, 14)
                    }
            }
            .buttonStyle(PressStyle(scale: 0.99))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
                ForEach(store.feed) { p in
                    PersonTile(person: p, selecting: store.selecting,
                               selected: store.selection.contains(p.id))
                    .onTapGesture {
                        if store.selecting { toggle(p.id) } else { path.append(.profile(p.id)) }
                    }
                    .onLongPressGesture(minimumDuration: 0.55) {
                        withAnimation(.smooth) {
                            store.selecting = true
                            store.selection.insert(p.id)
                        }
                    }
                    .draggable(String(p.id)) { PersonTile(person: p, selecting: false, selected: false).frame(width: 110) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let dragged = Int(raw),
                              let from = store.feed.firstIndex(where: { $0.id == dragged }),
                              let to = store.feed.firstIndex(where: { $0.id == p.id }) else { return false }
                        withAnimation(.smooth) {
                            store.reorder(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                        }
                        return true
                    }
                }
            }
        }
    }

    private func toggle(_ id: Int) {
        if store.selection.contains(id) { store.selection.remove(id) } else { store.selection.insert(id) }
        if store.selection.isEmpty { withAnimation(.smooth) { store.selecting = false } }
    }

    private var floatingButtons: some View {
        HStack {
            Button { showArchive = true } label: {
                Image(systemName: "archivebox.fill").font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.ink).frame(width: M.fab, height: M.fab)
            }
            .glass(Circle()).pressable(0.93)
            Spacer()
            Button { showCapture = true } label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.bg).frame(width: M.fab, height: M.fab)
                    .background(Color.ink, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            }
            .pressable(0.93)
        }
        .padding(.horizontal, M.gutter).padding(.bottom, 6)
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(store.selection.count) selected")
                .font(.system(size: 16, weight: .heavy)).tracking(-0.4).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            Chip(title: "Move", icon: "tag.fill") { showCategories = true }
            Chip(title: "Archive", icon: "archivebox.fill") {
                let ids = store.selection
                ids.forEach { store.archive($0) }
                withAnimation(.smooth) { store.selecting = false; store.selection = [] }
                toast = ToastState(message: "\(ids.count) archived") {
                    ids.forEach { store.restore($0) }
                }
            }
            Chip(title: "Done", solid: true) {
                withAnimation(.smooth) { store.selecting = false; store.selection = [] }
            }
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
        .glass()
        .padding(.horizontal, M.gutter).padding(.bottom, 6)
    }
}

// MARK: - Toast

struct ToastState: Identifiable {
    let id = UUID()
    let message: String
    var undo: (() -> Void)? = nil
}

struct ToastView: View {
    let state: ToastState
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 18) {
            Text(state.message).font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                .foregroundStyle(Color.ink)
            if let undo = state.undo {
                Chip(title: "Undo") { undo(); dismiss() }
            }
        }
        .padding(.leading, 22).padding(.trailing, state.undo == nil ? 22 : 8)
        .frame(height: 52)
        .glass()
        .padding(.bottom, 84)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(3.6))
            withAnimation(.smooth) { dismiss() }
        }
    }
}

// MARK: - Profile

struct ProfileScreen: View {
    let personID: Int
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var toast: ToastState?
    @State private var showMenu = false
    @State private var showAssign = false
    @State private var showRefresher = false
    @State private var editing: (section: Int, line: Int)? = nil
    @State private var draft = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var lineFocused: Bool

    private var person: Person? { store.person(personID) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()
            if let p = person {
                VStack(spacing: 0) {
                    HStack {
                        CircleButton(icon: "chevron.left") { dismiss() }
                        Spacer()
                        CircleButton(icon: "ellipsis") { showMenu = true }
                    }
                    .padding(.horizontal, M.gutter).padding(.top, 6)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 16) {
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    Avatar(person: p, size: 64)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color.bg)
                                                .frame(width: 24, height: 24)
                                                .background(Color.ink, in: Circle())
                                                .overlay(Circle().strokeBorder(Color.bg, lineWidth: 3))
                                                .offset(x: 3, y: 3)
                                        }
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(p.name).font(.system(size: 26, weight: .heavy)).tracking(-0.9)
                                        .foregroundStyle(Color.ink)
                                    Text(p.meta).snipText()
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.top, 26)

                            Chip(title: store.label(p.cat), icon: "tag.fill") { showAssign = true }
                                .padding(.top, 16)

                            ForEach(Array(p.sections.enumerated()), id: \.element.id) { si, sec in
                                VStack(alignment: .leading, spacing: 0) {
                                    SectionLabel(text: sec.title)
                                    Grouped {
                                        ForEach(Array(sec.lines.enumerated()), id: \.offset) { li, line in
                                            if li > 0 { Hairline(leading: 20) }
                                            lineRow(si: si, li: li, text: line)
                                        }
                                        Hairline(leading: 20)
                                        Button {
                                            var q = p
                                            q.sections[si].lines.append("")
                                            store.update(q)
                                            editing = (si, q.sections[si].lines.count - 1)
                                            draft = ""
                                            lineFocused = true
                                        } label: {
                                            HStack {
                                                Text("Add a line").font(.tBody).foregroundStyle(Color.ink2)
                                                Spacer()
                                                Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                                                    .foregroundStyle(Color.ink2)
                                            }
                                            .padding(.horizontal, 20).frame(minHeight: 52)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 30)
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                SectionLabel(text: "Photos")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(p.photos.enumerated()), id: \.offset) { i, data in
                                            if let img = UIImage(data: data) {
                                                Image(uiImage: img).resizable().scaledToFill()
                                                    .frame(width: 86, height: 110)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                    .overlay(alignment: .topTrailing) {
                                                        Button {
                                                            var q = p; q.photos.remove(at: i); store.update(q)
                                                        } label: {
                                                            Image(systemName: "xmark")
                                                                .font(.system(size: 10, weight: .heavy))
                                                                .foregroundStyle(.white)
                                                                .frame(width: 24, height: 24)
                                                                .background(.black.opacity(0.55), in: Circle())
                                                        }
                                                        .padding(5)
                                                    }
                                            }
                                        }
                                        PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                                            Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(Color.ink2)
                                                .frame(width: 86, height: 110)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .strokeBorder(Color.ink3, style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                            .padding(.top, 30)

                            Color.clear.frame(height: 150)
                        }
                        .padding(.horizontal, M.gutter)
                    }
                    .scrollIndicators(.hidden)
                }

                BottomFade()
                CTA(title: "Refresh my memory") { showRefresher = true }
                    .padding(.horizontal, M.gutterCTA).padding(.bottom, 6)
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("", isPresented: $showMenu, titleVisibility: .hidden) {
            Button("Change category") { showAssign = true }
            Button("Archive") {
                store.archive(personID)
                dismiss()
                toast = ToastState(message: "Archived") { store.restore(personID) }
            }
            Button("Delete", role: .destructive) {
                if let (gone, at) = store.delete(personID) {
                    dismiss()
                    toast = ToastState(message: "Deleted") { store.reinsert(gone, at: at) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAssign) {
            CategorySheet(mode: .assign(personID)) { _ in }
                .presentationDetents([.medium]).presentationCornerRadius(34)
        }
        .sheet(isPresented: $showRefresher) {
            RefresherSheet(personID: personID)
                .presentationDetents([.height(320)]).presentationCornerRadius(34)
        }
        .onChange(of: avatarItem) { _, item in
            Task {
                guard var p = person,
                      let data = try? await item?.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                p.avatar = img.downscaled(to: 520)
                store.update(p)
            }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                guard var p = person else { return }
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data), let jpeg = img.downscaled(to: 900) {
                        p.photos.append(jpeg)
                    }
                }
                store.update(p)
                photoItems = []
            }
        }
    }

    @ViewBuilder
    private func lineRow(si: Int, li: Int, text: String) -> some View {
        if editing?.section == si && editing?.line == li {
            TextField("", text: $draft, axis: .vertical)
                .font(.tBody).foregroundStyle(Color.ink)
                .focused($lineFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20).frame(minHeight: 52)
                .onAppear { draft = text; lineFocused = true }
                .onChange(of: lineFocused) { _, focused in if !focused { commit(si: si, li: li) } }
                .onSubmit { commit(si: si, li: li) }
        } else {
            Button {
                draft = text
                editing = (si, li)
                lineFocused = true
            } label: {
                Text(text).font(.tBody).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func commit(si: Int, li: Int) {
        guard var p = person, p.sections.indices.contains(si) else { editing = nil; return }
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty {
            p.sections[si].lines.remove(at: li)
            if p.sections[si].lines.isEmpty { p.sections.remove(at: si) }
        } else {
            p.sections[si].lines[li] = v
        }
        p.summary = String(p.sections.flatMap(\.lines).joined(separator: " ").prefix(120))
        store.update(p)
        editing = nil

        if let question = v.aiQuestion { answerInline(question, si: si, li: li) }
    }

    /// `@AI …` on a line answers itself where it stands.
    ///
    /// The question is put back verbatim if the answer never arrives, so a dead
    /// network costs a round trip and not the thing you wanted to ask.
    private func answerInline(_ question: String, si: Int, li: Int) {
        guard var p = person, p.sections.indices.contains(si),
              p.sections[si].lines.indices.contains(li) else { return }
        p.sections[si].lines[li] = "…"
        store.update(p)

        let note = p.sections.flatMap(\.lines).joined(separator: "\n")
        Task {
            let answer = await Intelligence.shared.ask(question, everyone: store.people, note: note, about: p)
            guard var fresh = person, fresh.sections.indices.contains(si),
                  fresh.sections[si].lines.indices.contains(li),
                  fresh.sections[si].lines[li] == "…" else { return }
            fresh.sections[si].lines[li] = answer ?? "@AI \(question)"
            fresh.summary = String(fresh.sections.flatMap(\.lines).joined(separator: " ").prefix(120))
            store.update(fresh)
        }
    }
}

extension UIImage {
    func downscaled(to maxSide: CGFloat) -> Data? {
        let s = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * s, height: size.height * s)
        let r = UIGraphicsImageRenderer(size: target)
        return r.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: 0.72)
    }
}

// MARK: - Search

struct SearchScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var understood: [SearchHit] = []
    @State private var answer: String?
    @State private var asking = false
    @FocusState private var focused: Bool
    let open: (Int) -> Void

    /// Same mention affordance as the capture card, so `@AI` means the same
    /// thing in both places the user can type it.
    private var mention: String? {
        guard let at = term.lastIndex(of: "@") else { return nil }
        let token = String(term[at...])
        guard !token.contains(" ") else { return nil }
        let low = token.lowercased()
        guard "@ai".hasPrefix(low) || "@ia".hasPrefix(low) else { return nil }
        return token
    }

    private var mentionChip: some View {
        Button {
            guard let at = term.lastIndex(of: "@") else { return }
            term.replaceSubrange(at..<term.endIndex, with: "@AI ")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.ink).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask AI").font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                        .foregroundStyle(Color.ink)
                    Text("Answers from everything you have written")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18).frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass()
    }

    /// The answer sits above the matches rather than replacing them: asking a
    /// question should not throw away the list you could still scroll.
    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(answer ?? "Thinking…")
                    .font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(answer == nil ? Color.ink2 : Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.smooth) { answer = nil; asking = false }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .floatCard()
    }

    /// Literal matches first — they are instant and always right. Anything the
    /// model found that the substring pass missed is appended, so the list can
    /// only ever grow: "fashion" keeps matching the word and starts matching
    /// Sofia, whose notes say Vogue Scandinavia and never say fashion.
    private var hits: [(person: Person, line: String)] {
        let literal = store.search(term)
        let seen = Set(literal.map(\.person.id))
        let extra = understood.compactMap { hit -> (person: Person, line: String)? in
            guard !seen.contains(hit.id), let p = store.person(hit.id) else { return nil }
            return (p, hit.line)
        }
        return literal + extra
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dismiss() }
                    Spacer()
                    Text("Search").navTitle()
                    Spacer()
                    Color.clear.frame(width: M.circle, height: M.circle)
                }
                .padding(.horizontal, M.gutter).padding(.top, 6)

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.5))
                    TextField("Who works in fashion?", text: $term)
                        .font(.system(size: 17, weight: .bold)).tracking(-0.42)
                        .foregroundStyle(Color.ink)
                        .focused($focused)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 19).frame(height: 52)
                .glass()
                .padding(.horizontal, M.gutter).padding(.top, 26)

                if mention != nil { mentionChip.padding(.horizontal, M.gutter).padding(.top, 10) }

                ScrollView {
                    let hits = hits
                    if answer != nil || asking { answerCard.padding(.top, 20) }
                    if term.isEmpty {
                        Text("Search people and memories.\nType @AI to ask a question instead.")
                            .multilineTextAlignment(.center).snipText().padding(.top, 60)
                    } else if hits.isEmpty && answer == nil && !asking {
                        Text(term.aiQuestion == nil ? "Nothing on that." : "No answer to that.")
                            .snipText().padding(.top, 60)
                    } else if !hits.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(hits.enumerated()), id: \.offset) { i, hit in
                                if i > 0 { Rectangle().fill(Color.hairline).frame(height: 1) }
                                Button { open(hit.person.id) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hit.person.name + (hit.person.archived ? " · archived" : ""))
                                            .font(.system(size: 17, weight: .heavy)).tracking(-0.5)
                                            .foregroundStyle(Color.ink)
                                        Text("“\(hit.line)”").snipText()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 17)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 20)
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, M.gutter)
            }
        }
        .navigationBarHidden(true)
        .onAppear { focused = true }
        .task(id: term) {
            understood = []
            let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count > 2 else { return }
            // one pass per question, not one per keystroke; `task(id:)` cancels
            // the previous attempt for us
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            // "@AI who is Jean?" is a question to answer, not a string to match
            if let question = q.aiQuestion {
                asking = true
                answer = nil
                let reply = await Intelligence.shared.ask(question, everyone: store.people)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth) {
                    answer = reply ?? "No answer to that."
                    asking = false
                }
                return
            }
            understood = await Intelligence.shared.answer(q, over: store.people) ?? []
        }
    }
}

// MARK: - Capture

struct CaptureSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var dictation = Dictation()
    @State private var typed = ""          // what the keyboard put in
    @State private var prefix = ""         // what was there when dictation started
    @State private var thinking = false    // an @AI line is out for an answer
    @FocusState private var focused: Bool
    let onSave: (Int?) -> Void

    /// While listening the field is prefix + live transcript; otherwise it is
    /// whatever the keyboard holds. Binding it this way means voice and keyboard
    /// write into the same card with no mode switch, which is the whole point.
    private var text: Binding<String> {
        Binding(
            get: { dictation.status.isListening ? prefix + dictation.transcript : typed },
            set: { typed = $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dictation.stop(); dismiss(); onSave(nil) }
                    Spacer()
                    Text("New meeting").navTitle()
                    Spacer()
                    CircleButton(icon: "checkmark") { save() }
                }
                .padding(.horizontal, M.gutter).padding(.top, 14)

                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("Who did you meet?")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink3)
                            .padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .frame(minHeight: 290)
                }
                .padding(20)
                .floatCard()
                .padding(.horizontal, M.gutter).padding(.top, 56)

                Spacer()
            }

            // sits in the bottom layer, not the scrolling content, so it can never
            // slide under the toolbar when the card grows
            VStack(spacing: 14) {
                if mention != nil { mentionChip.padding(.horizontal, M.gutter) }
                if let message = errorMessage {
                    Text(message).snipText().multilineTextAlignment(.center)
                        .padding(.horizontal, M.gutterCTA)
                }
                HStack {
                    CircleButton(icon: "keyboard.fill") { dictation.stop(); focused = true }
                    Spacer()
                    dictateButton
                    Spacer()
                    CircleButton(icon: "trash.fill",
                                 idle: !hasText,
                                 tint: hasText ? .danger : nil) {
                        dictation.stop(); typed = ""; prefix = ""
                    }
                    .animation(.smooth(duration: 0.2), value: hasText)
                }
                .padding(.horizontal, M.gutter)
            }
            .padding(.bottom, 6)
        }
        .onAppear { focused = true }
        .onDisappear { dictation.stop() }
        .onChange(of: typed) { _, new in askInline(new) }
    }

    /// A line that reads `@AI …` answers itself as soon as you press return.
    ///
    /// Fires on the newline rather than on a pause: mid-sentence hesitation is not
    /// a question, and asking on every keystroke would send a dozen half-typed
    /// ones. Setting `typed` in here re-enters — the placeholder line no longer
    /// starts with `@AI`, so the second pass falls straight through.
    private func askInline(_ value: String) {
        guard !thinking, value.hasSuffix("\n") else { return }
        var lines = value.components(separatedBy: "\n")
        lines.removeLast()
        guard let question = lines.last?.aiQuestion else { return }

        thinking = true
        let context = lines.dropLast().joined(separator: "\n")
        lines[lines.count - 1] = Self.pending
        typed = lines.joined(separator: "\n") + "\n"

        Task {
            let answer = await Intelligence.shared.ask(question, everyone: store.people, note: context)
            var out = typed.components(separatedBy: "\n")
            if let i = out.lastIndex(of: Self.pending) {
                out[i] = answer ?? "@AI \(question)"
                typed = out.joined(separator: "\n")
            }
            thinking = false
        }
    }

    private static let pending = "…"

    private var errorMessage: String? {
        switch dictation.status {
        case .denied(let m), .unavailable(let m): m
        default: nil
        }
    }

    private var hasText: Bool {
        !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The half-typed `@…` at the caret, while it could still become a mention.
    ///
    /// Instagram shows you the handle you are reaching for before you finish
    /// typing it; this is the same idea with one entry in the list. It stops
    /// being a draft the moment a space is typed, because by then the question
    /// itself has started.
    private var mention: String? {
        guard !dictation.status.isListening else { return nil }
        let line = typed.components(separatedBy: "\n").last ?? ""
        guard let at = line.lastIndex(of: "@") else { return nil }
        let token = String(line[at...])
        guard !token.contains(" ") else { return nil }
        let low = token.lowercased()
        guard "@ai".hasPrefix(low) || "@ia".hasPrefix(low) else { return nil }
        return token
    }

    private var mentionChip: some View {
        Button {
            var lines = typed.components(separatedBy: "\n")
            guard var last = lines.last, let at = last.lastIndex(of: "@") else { return }
            last.replaceSubrange(at..<last.endIndex, with: "@AI ")
            lines[lines.count - 1] = last
            typed = lines.joined(separator: "\n")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.ink).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask AI").font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                        .foregroundStyle(Color.ink)
                    Text("Answers here, from everything you have written")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "return").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 18).frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // The only animated element in the app: the dot breathes and a specular band
    // sweeps the glass. Light over a liquid, not a status indicator.
    private var dictateButton: some View {
        let live = dictation.status.isListening
        return Button {
            if live {
                typed = prefix + dictation.transcript
                dictation.stop()
            } else {
                prefix = typed.isEmpty ? "" : typed + " "
                focused = false
                Task { await dictation.start() }
            }
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .strokeBorder(live ? Color.clear : Color.inkIdle, lineWidth: 2.4)
                    .background(Circle().fill(live ? Color.ink : Color.clear))
                    .frame(width: 15, height: 15)
                    .scaleEffect(live ? 1.22 : 1)
                    .animation(live ? .easeInOut(duration: 0.725).repeatForever(autoreverses: true) : .default,
                               value: live)
                Text(live ? "Listening" : "Dictate")
                    .font(.system(size: 17, weight: .heavy)).tracking(-0.42)
                    .foregroundStyle(live ? Color.ink : Color.inkIdle)
            }
            .padding(.horizontal, 26).frame(height: M.circle)
        }
        .glass()
        .pressable(0.96)
    }

    private func save() {
        let final = text.wrappedValue
        dictation.stop()
        guard let p = store.parse(final) else { dismiss(); onSave(nil); return }
        store.add(p)
        dismiss()
        onSave(p.id)
        // detached from the sheet's lifetime on purpose: the sheet is already
        // gone by the time this lands on the card behind it
        Task { await store.refine(p.id, from: final) }
    }
}
