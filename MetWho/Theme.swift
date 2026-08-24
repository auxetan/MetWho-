import SwiftUI

// Every value here is sampled from the reference screenshots at 1290×2796 @3x.
// See ../../design/01-tokens.md for the provenance of each one.

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg          = dyn(0xF6F6F6, 0x000000)
    static let surface     = dyn(0xFFFFFF, 0x242424)
    static let surfaceHigh = dyn(0xFBFBFB, 0x1E1E1E)
    static let ink         = dyn(0x0E0E0E, 0xFFFFFF)
    static let ink2        = dyn(0x86868B, 0x8A8A8E)
    static let ink3        = dyn(0xB8B8BC, 0x6A6A6E)
    static let inkIdle     = dyn(0xACACAC, 0x6E6E6E)
    /// The only colour in a black-and-white app. It appears on exactly one
    /// control — the bin, once it has something to delete — which is what keeps
    /// it meaning "this destroys something" rather than becoming decoration.
    static let danger      = dyn(0xE5322D, 0xFF6961)
    static let hairline    = dyn(0xE7E7E7, 0x333333)
    static let fillSoft    = dyn(0xE9E9EB, 0x2C2C2E)
    static let avatarBG    = dyn(0xEEEEEE, 0x2E2E2E)
    static let glassA      = dyn(0xF7F7F7, 0x252525)
    static let glassB      = dyn(0xFAFAFA, 0x1F1F1F)
    static let ctaBG       = dyn(0x0E0E0E, 0xFFFFFF)
    static let ctaFG       = dyn(0xFFFFFF, 0x0E0E0E)
}

enum M {
    static let gutter: CGFloat = 21
    static let gutterCTA: CGFloat = 28
    static let rCard: CGFloat = 26
    static let rFloat: CGFloat = 30
    static let rTile: CGFloat = 22
    static let hCTA: CGFloat = 56
    static let hRow: CGFloat = 64
    static let circle: CGFloat = 48
    static let fab: CGFloat = 60
    static let fade: CGFloat = 150
}

// The references are set in a geometric face (Gilroy or Greycliff CF, both
// commercial). Until one is licensed and bundled, this is SF Pro pushed to the
// same weight and tracking — heavy everywhere, grey text included.
extension Font {
    static let tDisplay = Font.system(size: 31, weight: .heavy)
    static let tNav     = Font.system(size: 18, weight: .heavy)
    static let tCard    = Font.system(size: 19, weight: .heavy)
    static let tRow     = Font.system(size: 17, weight: .heavy)
    static let tBody    = Font.system(size: 16, weight: .semibold)
    static let tSnip    = Font.system(size: 15, weight: .semibold)
    static let tSect    = Font.system(size: 16, weight: .heavy)
    static let tMeta    = Font.system(size: 13, weight: .bold)
    static let tCTA     = Font.system(size: 18, weight: .heavy)
}

/// Light type on a dark ground optically gains weight: the same 800 that reads
/// ExtraBold on white reads heavier than intended on `#242424`, and heaviest of
/// all against the pure-black page. The heavy roles therefore step down one
/// notch in dark so they *read* at the weight rule 3 asks for — the rule is
/// about how the type lands, and matching the number while missing the look
/// would be the literal reading of it.
///
/// The 600 roles are left alone. They bloom far less, and lightening them would
/// walk toward the weight-400 run the rule exists to forbid.
private struct Typo: ViewModifier {
    let size: CGFloat
    let tracking: CGFloat
    let colour: Color
    var heavy = true
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: heavy ? (scheme == .dark ? .bold : .heavy) : .semibold))
            .tracking(tracking)
            .foregroundStyle(colour)
    }
}

extension View {
    private func typo(_ size: CGFloat, _ tracking: CGFloat, _ colour: Color, heavy: Bool = true) -> some View {
        modifier(Typo(size: size, tracking: tracking, colour: colour, heavy: heavy))
    }
    func display() -> some View { typo(31, -1.05, .ink) }
    func navTitle() -> some View { typo(18, -0.45, .ink) }
    func cardTitle() -> some View { typo(19, -0.55, .ink) }
    func rowLabel() -> some View { typo(17, -0.42, .ink) }
    func sectLabel() -> some View { typo(16, -0.4, .ink2) }
    func bodyText() -> some View { typo(16, -0.24, .ink2, heavy: false) }
    func snipText() -> some View { typo(15, -0.22, .ink2, heavy: false) }
    func metaText() -> some View { font(.tMeta).tracking(-0.13).foregroundStyle(Color.ink2) }
}

// MARK: - Springs
// Matches the CSS build: real springs, not eyeballed curves.
extension Animation {
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 1.0)
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.48, dampingFraction: 0.66)
}

// MARK: - Liquid glass
// The measurement that carries the whole style: the fill sits one to three
// values above the page. What draws the control is the hairline, the inner top
// highlight and a soft shadow — never a white fill.
struct Glass: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule(style: .continuous))
    @Environment(\.colorScheme) private var scheme
    @State private var held = false
    @State private var contact: CGPoint = .zero
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(LinearGradient(colors: [.glassA, .glassB], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // the specular highlight gathers where the finger is
                        if held, size.width > 0 {
                            RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.10 : 0.85), .clear],
                                           center: UnitPoint(x: contact.x / max(size.width, 1),
                                                             y: contact.y / max(size.height, 1)),
                                           startRadius: 0, endRadius: 88)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                        }
                    }
                    // AnyShape is not InsettableShape, so this is stroke() rather
                    // than strokeBorder() — at 1pt the half-point bleed is invisible
                    .overlay { shape.stroke(Color.primary.opacity(scheme == .dark ? 0.09 : 0.055), lineWidth: 1) }
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 2, y: 2)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.055), radius: 9, y: 6)
            }
            .background { GeometryReader { g in Color.clear.onAppear { size = g.size } } }
            .scaleEffect(held ? 0.952 : 1)
            .offset(x: lean.width, y: lean.height)
            .animation(held ? .snappy : .bouncy, value: held)
            .animation(.snappy, value: contact)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in contact = v.location; if !held { held = true } }
                    .onEnded { _ in held = false }
            )
    }

    // it leans into the finger by a few points and no further: past that it stops
    // reading as a surface deforming and starts reading as an object sliding
    private var lean: CGSize {
        guard held, size.width > 0 else { return .zero }
        return CGSize(width: (contact.x / size.width - 0.5) * 5,
                      height: (contact.y / size.height - 0.5) * 5)
    }
}

extension View {
    func glass(_ shape: some Shape = Capsule(style: .continuous)) -> some View {
        modifier(Glass(shape: AnyShape(shape)))
    }
    func card(_ radius: CGFloat = M.rCard) -> some View {
        background(Color.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.025), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.03), radius: 7, y: 2)
    }
    func floatCard() -> some View {
        background(Color.surfaceHigh, in: RoundedRectangle(cornerRadius: M.rFloat, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.055), radius: 14, y: 6)
            .shadow(color: .black.opacity(0.035), radius: 28, y: 14)
    }
    func pressable() -> some View { buttonStyle(PressStyle()) }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.975
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

// MARK: - The fade
// Cards are never cut. They pass under the buttons through an accumulating
// blur: three materials, each masked to reveal a band nearer the bottom than
// the last, then a tint that stops short of opaque so the cards stay legible.
struct BottomFade: View {
    var body: some View {
        // The fade has to reach the physical bottom of the screen, not the bottom
        // of the safe area — otherwise a card reappears sharp in the home
        // indicator strip, which is the exact hard edge this exists to prevent.
        GeometryReader { g in
            layers
                .frame(height: M.fade + g.safeAreaInsets.bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var layers: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: 0.40),
                                             .init(color: .clear, location: 0.72)],
                                     startPoint: .bottom, endPoint: .top))
            Rectangle().fill(.thinMaterial)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: 0.24),
                                             .init(color: .clear, location: 0.52)],
                                     startPoint: .bottom, endPoint: .top))
            Rectangle().fill(.regularMaterial)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: 0.08),
                                             .init(color: .clear, location: 0.28)],
                                     startPoint: .bottom, endPoint: .top))
            LinearGradient(stops: [.init(color: .bg.opacity(0.88), location: 0),
                                   .init(color: .bg.opacity(0.58), location: 0.32),
                                   .init(color: .bg.opacity(0.18), location: 0.66),
                                   .init(color: .bg.opacity(0), location: 1)],
                           startPoint: .bottom, endPoint: .top)
        }
    }
}

// MARK: - Building blocks

struct CircleButton: View {
    let icon: String
    var idle = false
    var size: CGFloat = 26
    /// Overrides the glyph colour outright. Used by the capture toolbar's bin,
    /// which turns red the moment there is something to throw away — the button
    /// is always there, but only sometimes worth pressing.
    var tint: Color? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.72, weight: .bold))
                .foregroundStyle(tint ?? (idle ? Color.inkIdle : Color.ink))
                .frame(width: M.circle, height: M.circle)
        }
        .glass(Circle())
        .pressable()
    }
}

/// Swipe-left actions for a card that is not in a `List`.
///
/// The first two attempts imported iOS's own swipe: full-height coloured panels
/// butted together behind the row. Both were wrong for this app, and not because
/// of the colour.
///
/// The shape vocabulary is four shapes and "nothing else, no right angles". A
/// glyph button here is a Circle 48, the same one the header and the archive FAB
/// use — so that is what the swipe reveals. Severity is carried by value, the
/// way it is everywhere else: Archive's glyph sits at `inkIdle`, Delete's at
/// full `ink`.
///
/// Motion is one spring on one property. `05-motion.md` allows `.snappy` for
/// presses and toggles and says "one thing moves at a time", which rules out the
/// widening button and the rubber-band resistance the previous version had.
/// Nothing here animates except the card's own x.
struct SwipeRow<Content: View>: View {
    let onTap: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var open = false

    /// Two Circle 48s and the gap between them.
    private var reveal: CGFloat { M.circle * 2 + 12 }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 12) {
                CircleButton(icon: "archivebox.fill", idle: true) { close(); onArchive() }
                CircleButton(icon: "trash.fill") { close(); onDelete() }
            }
            // fades with the reveal so the buttons arrive with the movement
            // rather than sitting there waiting to be uncovered
            .opacity(Double(min(1, -offset / reveal)))

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .onTapGesture { open ? close() : onTap() }
                // not a Button: a Button's own gesture beats a parent drag and
                // the card never moves
                .gesture(drag)
        }
        .onDisappear { offset = 0; open = false }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { g in
                // vertical intent belongs to the scroll view
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                let raw = (open ? -reveal : 0) + g.translation.width
                offset = max(-reveal, min(0, raw))
            }
            .onEnded { g in
                let raw = (open ? -reveal : 0) + g.translation.width
                withAnimation(.snappy) {
                    open = -raw > reveal / 2
                    offset = open ? -reveal : 0
                }
            }
    }

    private func close() {
        withAnimation(.snappy) { offset = 0; open = false }
    }
}

struct CTA: View {
    let title: String
    var icon: String? = nil
    var inCard = false
    var secondary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(inCard ? .system(size: 19, weight: .heavy) : .tCTA).tracking(-0.54)
            }
            .frame(maxWidth: .infinity)
            .frame(height: inCard ? 62 : M.hCTA)
            .foregroundStyle(secondary ? Color.ink : Color.ctaFG)
            .background(secondary ? Color.fillSoft : Color.ctaBG, in: Capsule(style: .continuous))
            .shadow(color: secondary ? .clear : .black.opacity(0.10), radius: 10, y: 5)
        }
        .pressable()
    }
}

struct Chip: View {
    let title: String
    var icon: String? = nil
    var solid = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.system(size: 14, weight: .heavy)).tracking(-0.28)
            }
            .padding(.horizontal, 13).frame(height: 34)
            .foregroundStyle(solid ? Color.ctaFG : Color.ink)
            .background(solid ? Color.ctaBG : Color.fillSoft, in: Capsule(style: .continuous))
        }
        .pressable(0.94)
    }
}

extension View { func pressable(_ s: CGFloat) -> some View { buttonStyle(PressStyle(scale: s)) } }

struct Avatar: View {
    let person: Person
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.avatarBG)
            if let d = person.avatar, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(String(person.name.prefix(1)))
                    .font(.system(size: size * 0.39, weight: .heavy)).tracking(-0.4)
                    .foregroundStyle(Color.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).sectLabel()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22).padding(.bottom, 10)
    }
}

struct Hairline: View {
    var leading: CGFloat = 60
    var body: some View {
        Rectangle().fill(Color.hairline).frame(height: 1)
            .padding(.leading, leading).padding(.trailing, 20)
    }
}

struct SettingsRow: View {
    var icon: String? = nil
    let label: String
    var sub: String? = nil
    var value: String? = nil
    var accessory: Accessory = .chevron
    var action: () -> Void = {}

    enum Accessory { case chevron, check, none }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink).frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).rowLabel()
                    if let sub { Text(sub).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink2) }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.system(size: 17, weight: .bold)).tracking(-0.42).foregroundStyle(Color.ink2)
                }
                switch accessory {
                case .chevron: Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink3)
                case .check:   Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                case .none:    EmptyView()
                }
            }
            .padding(.leading, icon == nil ? 20 : 24).padding(.trailing, 20)
            .frame(minHeight: M.hRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A grouped card: rows on a 64pt rhythm with a hairline inset to the label.
struct Grouped<Content: View>: View {
    var hairlineInset: CGFloat = 60
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .card()
    }
}
