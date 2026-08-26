import SwiftUI

// MARK: - Categories
// One sheet, three modes: filter the feed, move one person, move a selection.

struct CategorySheet: View {
    enum Mode: Equatable { case filter, assign(Int) }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onToast: (ToastState) -> Void

    @State private var editing = false
    @State private var newName = ""
    @FocusState private var fieldFocused: Bool

    private var isAssign: Bool { if case .assign = mode { true } else { false } }
    private var rows: [Category] { isAssign ? store.categories : store.visibleCategories }
    private var selected: String? {
        switch mode {
        case .filter: store.prefs.cat
        case .assign(let id): store.person(id)?.cat
        }
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(isAssign ? "Move to" : "Show").sectLabel().padding(.leading, 22)
                        Spacer()
                        if !isAssign {
                            Chip(title: editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                        }
                    }
                    .padding(.bottom, 10)

                    Grouped {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, cat in
                            if i > 0 { Hairline(leading: 22) }
                            row(cat)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("New category", text: $newName)
                            .font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                            .foregroundStyle(Color.ink)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .padding(.horizontal, 18).frame(height: 44)
                            .background(Color.surface, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                        Chip(title: "Add", solid: true, action: add)
                            .frame(height: 44)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 12)
                }
                .padding(.horizontal, M.gutter).padding(.top, 22)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func row(_ cat: Category) -> some View {
        let fixed = cat.id == "all" || cat.id == "unsorted"
        Button {
            switch mode {
            case .filter:
                store.prefs.cat = cat.id; store.save()
            case .assign(let id):
                if store.selecting, !store.selection.isEmpty {
                    let n = store.selection.count
                    store.move(store.selection, to: cat.id)
                    store.selecting = false; store.selection = []
                    onToast(ToastState(message: "\(n) moved to \(cat.label)"))
                } else if var p = store.person(id) {
                    p.cat = cat.id; store.update(p)
                }
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(cat.label).font(.system(size: 17, weight: .heavy)).tracking(-0.42)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                if editing && !fixed && !isAssign {
                    Button {
                        withAnimation(.smooth) { store.deleteCategory(cat.id) }
                    } label: {
                        Image(systemName: "minus").font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 30, height: 30)
                            .background(Color.fillSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                } else if cat.id == selected {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.ink)
                } else {
                    Text("\(store.count(cat.id))")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink2)
                }
            }
            .padding(.leading, 22).padding(.trailing, 20)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() {
        store.addCategory(newName)
        newName = ""
        fieldFocused = false
    }
}

// MARK: - Archive

struct ArchiveSheet: View {
    @Environment(Store.self) private var store
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Archived")
                    if store.archived.isEmpty {
                        Grouped {
                            Text("Nothing archived.").snipText()
                                .frame(maxWidth: .infinity).padding(.vertical, 34)
                        }
                    } else {
                        Grouped {
                            ForEach(Array(store.archived.enumerated()), id: \.element.id) { i, p in
                                if i > 0 { Hairline(leading: 20) }
                                HStack(spacing: 14) {
                                    Avatar(person: p, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                                            .foregroundStyle(Color.ink)
                                        Text(p.meta).font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.ink2)
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
                .padding(.horizontal, M.gutter).padding(.top, 22)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Places

struct PlacesSheet: View {
    @Environment(Store.self) private var store
    let open: (Int) -> Void
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Places")
                    if store.placesByCity.isEmpty {
                        Grouped {
                            Text("No places yet.").snipText()
                                .frame(maxWidth: .infinity).padding(.vertical, 34)
                        }
                    }
                    ForEach(store.placesByCity, id: \.city) { entry in
                        Grouped {
                            HStack {
                                Text(entry.city).rowLabel()
                                Spacer()
                                Text("\(entry.people.count)")
                                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.ink2)
                            }
                            .padding(.horizontal, 20).frame(minHeight: 52)
                            ForEach(entry.people) { p in
                                Hairline(leading: 20)
                                Button { open(p.id) } label: {
                                    HStack(spacing: 14) {
                                        Avatar(person: p, size: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name).font(.system(size: 16, weight: .heavy)).tracking(-0.4)
                                                .foregroundStyle(Color.ink)
                                            Text(p.meta).font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.ink2)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink3)
                                    }
                                    .padding(.horizontal, 20).frame(minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 14)
                    }
                }
                .padding(.horizontal, M.gutter).padding(.top, 22)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Refresher

struct RefresherSheet: View {
    @Environment(Store.self) private var store
    @State private var briefed: [String] = []
    let personID: Int

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if let p = store.person(personID) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).cardTitle()
                    // Three lines, never four. If the model produces more, they get cut.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines(for: p).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 15, weight: .semibold)).tracking(-0.22)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 14)
                    Text("Seen \(relative(p.date))").metaText().padding(.top, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .floatCard()
                .padding(.horizontal, M.gutter)
                // the stored lines are already on screen; if a better three come
                // back they swap in, and if they never do nobody knows to wait
                .task(id: personID) {
                    briefed = await Intelligence.shared.brief(for: p) ?? []
                }
            }
        }
    }

    /// Capture order until the model reorders it — what you owe someone matters
    /// more than where you met them, but only the model can tell which is which.
    private func lines(for p: Person) -> [String] {
        briefed.isEmpty ? Array(p.sections.flatMap(\.texts).prefix(3)) : briefed
    }

    private func relative(_ d: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: d, to: .now).day ?? 0
        return switch days {
        case ..<1: "today"
        case 1: "yesterday"
        case ..<30: "\(days) days ago"
        default: "\(days / 30) months ago"
        }
    }
}

/// Write anything about someone; the app works out where it goes.
///
/// The per-section "Add a line" made you pick the heading first, which is the
/// form S2 refuses — "the user is never asked to fill in a field". Here you
/// write the thing and it is filed for you, tidied into the card's voice, and
/// it becomes part of what the model reads when you ask about that person later.
struct AddLineSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    let personID: Int

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleButton(icon: "xmark") { dismiss() }
                    Spacer()
                    Text(store.person(personID)?.name ?? "Add").navTitle()
                    Spacer()
                    CircleButton(icon: "checkmark") { save() }
                }
                .padding(.horizontal, M.gutter).padding(.top, 14)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What else do you remember?")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink3)
                            .padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .frame(minHeight: 120)
                }
                .padding(20)
                .floatCard()
                .padding(.horizontal, M.gutter).padding(.top, 22)

                Spacer(minLength: 0)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        let line = text
        dismiss()
        // filed after the sheet is gone: the card behind fills itself in
        Task { await store.addLine(line, to: personID) }
    }
}
