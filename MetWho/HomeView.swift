import SwiftUI

// MARK: - Header

struct HeaderPillSelect: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(label).font(.system(size: 17, weight: .heavy)).tracking(-0.42)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.ink)
            .padding(.leading, 20).padding(.trailing, 18)
            .frame(height: M.circle)
        }
        .glass()
        .pressable(0.97)
    }
}

/// The three-icon pill. Sliding across it moves a lozenge that stretches to
/// cover both icons then contracts onto the target — the liquid morph. A
/// lozenge that simply slides reads as a tab bar, not as a material.
struct HeaderPillGroup: View {
    let icons: [String]
    let onPick: (Int) -> Void

    @State private var frames: [CGRect] = []
    @State private var active: Int? = nil
    @State private var lozenge: CGRect = .zero
    @State private var showLozenge = false

    var body: some View {
        HStack(spacing: 25) {
            ForEach(icons.indices, id: \.self) { i in
                Image(systemName: icons[i])
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 24, height: 24)
                    .offset(x: nudge(i))
                    .background { GeometryReader { g in
                        Color.clear.preference(key: IconFrames.self,
                                               value: [i: g.frame(in: .named("pill"))])
                    } }
            }
        }
        .padding(.horizontal, 19)
        .frame(height: M.circle)
        .coordinateSpace(name: "pill")
        .onPreferenceChange(IconFrames.self) { d in
            frames = (0..<icons.count).map { d[$0] ?? .zero }
        }
        .background {
            Capsule(style: .continuous)
                .fill(Color.ink.opacity(showLozenge ? 0.085 : 0))
                .frame(width: lozenge.width, height: M.circle - 10)
                .position(x: lozenge.midX, y: M.circle / 2)
                .animation(.smooth, value: lozenge)
                .animation(.easeOut(duration: 0.17), value: showLozenge)
        }
        .glass()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in travel(to: v.location.x) }
                .onEnded { _ in
                    if let a = active { onPick(a) }
                    showLozenge = false; active = nil
                }
        )
    }

    private func nudge(_ i: Int) -> CGFloat {
        guard let a = active, a != i else { return 0 }
        return i < a ? -3 : 3
    }

    private func travel(to x: CGFloat) {
        guard !frames.isEmpty else { return }
        let target = frames.indices.min { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) } ?? 0
        guard target != active else { return }
        let pad: CGFloat = 13
        let to = frames[target].insetBy(dx: -pad, dy: 0)
        if !showLozenge {
            lozenge = to
            showLozenge = true
        } else {
            // stretch to cover both, then contract onto the target
            let union = lozenge.union(to)
            withAnimation(.smooth) { lozenge = union }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.smooth) { lozenge = to }
            }
        }
        active = target
    }
}

private struct IconFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, b in b }
    }
}

// MARK: - Cards

struct PersonCard: View {
    let person: Person
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Avatar(person: person, size: 46)
            VStack(alignment: .leading, spacing: 0) {
                Text(person.name).font(.system(size: 18, weight: .heavy)).tracking(-0.54)
                    .foregroundStyle(Color.ink)
                Text(person.meta).font(.tMeta).foregroundStyle(Color.ink2).padding(.top, 3)
                Text(person.summary).snipText().lineLimit(2).padding(.top, 9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PersonTile: View {
    let person: Person
    var selecting: Bool
    var selected: Bool
    var body: some View {
        VStack(spacing: 9) {
            Avatar(person: person, size: 44)
            Text(person.name).font(.system(size: 13.5, weight: .heavy)).tracking(-0.34)
                .multilineTextAlignment(.center).lineLimit(2)
                .foregroundStyle(Color.ink)
        }
        .padding(.top, 15).padding(.bottom, 13).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .card(M.rTile)
        .overlay(alignment: .topTrailing) {
            if selecting {
                ZStack {
                    Circle().fill(selected ? Color.ink : Color.surface)
                    Circle().strokeBorder(selected ? Color.ink : Color.ink3, lineWidth: 2)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.surface)
                    }
                }
                .frame(width: 22, height: 22).padding(8)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: M.rTile, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: 2)
            }
        }
    }
}

// MARK: - Globe
// A dot-matrix sphere: ~2 800 points from a Fibonacci lattice, filtered to land
// by point-in-polygon against coarse rings. The rings are approximate on
// purpose — at 250pt they read as Earth. Swap them for GeoJSON and none of the
// projection changes.

enum GlobeData {
    static let rings: [[(Double, Double)]] = [
        [(-168,65),(-140,70),(-120,72),(-95,73),(-80,70),(-60,58),(-52,47),(-66,44),(-75,35),(-81,25),
         (-97,26),(-107,23),(-115,30),(-125,40),(-130,55),(-150,60)],
        [(-92,17),(-83,9),(-77,8),(-62,11),(-50,0),(-35,-6),(-38,-22),(-48,-28),(-58,-38),(-66,-50),
         (-72,-54),(-75,-45),(-71,-30),(-70,-18),(-80,-5),(-79,2),(-84,10)],
        [(-10,36),(-9,44),(-2,49),(4,52),(8,58),(5,62),(15,69),(30,71),(60,72),(90,76),(110,74),(140,72),
         (160,70),(170,66),(160,60),(142,54),(130,44),(122,40),(122,32),(110,20),(100,10),(95,16),(88,22),
         (80,10),(73,20),(62,25),(57,30),(48,30),(44,42),(36,36),(28,36),(12,38)],
        [(-17,15),(-16,28),(-6,36),(10,37),(25,32),(33,31),(43,12),(51,12),(42,-2),(40,-12),(35,-24),
         (26,-34),(18,-34),(12,-18),(9,-1),(-8,4),(-13,9)],
        [(113,-22),(122,-18),(130,-12),(142,-11),(147,-19),(153,-28),(150,-37),(141,-38),(130,-32),(118,-35)],
        [(-45,60),(-30,68),(-22,72),(-30,82),(-50,82),(-60,76),(-55,66)],
    ]

    static let cities: [String: (Double, Double)] = [
        "Paris": (48.85, 2.35), "Lisbon": (38.72, -9.14), "Porto": (41.15, -8.61),
        "Stockholm": (59.33, 18.07), "New York": (40.71, -74.01), "São Paulo": (-23.55, -46.63),
    ]

    static func onLand(_ lon: Double, _ lat: Double) -> Bool {
        for ring in rings {
            var hit = false
            var j = ring.count - 1
            for i in ring.indices {
                let (xi, yi) = ring[i], (xj, yj) = ring[j]
                if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { hit.toggle() }
                j = i
            }
            if hit { return true }
        }
        return false
    }

    static let points: [SIMD3<Double>] = {
        var out: [SIMD3<Double>] = []
        let n = 11000
        let ga = Double.pi * (3 - 5.squareRoot())
        for i in 0..<n {
            let y = 1 - (Double(i) / Double(n - 1)) * 2
            let r = (1 - y * y).squareRoot()
            let th = ga * Double(i)
            let x = cos(th) * r, z = sin(th) * r
            if onLand(atan2(z, x) * 180 / .pi, asin(y) * 180 / .pi) { out.append(SIMD3(x, y, z)) }
        }
        return out
    }()

    static func xyz(_ lat: Double, _ lon: Double) -> SIMD3<Double> {
        let a = lat * .pi / 180, o = lon * .pi / 180
        return SIMD3(cos(a) * cos(o), sin(a), cos(a) * sin(o))
    }
}

struct GlobeView: View {
    let places: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let spin = reduceMotion ? -0.6 : -0.6 + t * 0.13
                let tilt = 0.26
                let R = min(size.width, size.height) * 0.46
                let c = CGPoint(x: size.width / 2, y: size.height / 2)

                ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 1.22, y: c.y - R * 1.22,
                                                width: R * 2.44, height: R * 2.44)),
                         with: .radialGradient(Gradient(stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.20), location: 0.72),
                            .init(color: .white.opacity(0), location: 1)]),
                            center: c, startRadius: R * 0.80, endRadius: R * 1.22))

                func project(_ p: SIMD3<Double>) -> (CGPoint, Double) {
                    let X = p.x * cos(spin) + p.z * sin(spin)
                    let Z = -p.x * sin(spin) + p.z * cos(spin)
                    let Y2 = p.y * cos(tilt) - Z * sin(tilt)
                    let Z2 = p.y * sin(tilt) + Z * cos(tilt)
                    return (CGPoint(x: c.x + X * R, y: c.y - Y2 * R), Z2)
                }

                for p in GlobeData.points {
                    let (pt, depth) = project(p)
                    guard depth > 0.02 else { continue }
                    ctx.fill(Path(CGRect(x: pt.x, y: pt.y, width: 1.4, height: 1.4)),
                             with: .color(.white.opacity(0.18 + 0.80 * depth)))
                }

                let pulse = 0.5 + 0.5 * sin(t * 1.6)
                for city in places {
                    guard let (la, lo) = GlobeData.cities[city] else { continue }
                    let (pt, depth) = project(GlobeData.xyz(la, lo))
                    guard depth > 0.05 else { continue }
                    let halo = 3.4 + pulse * 3.6
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - halo, y: pt.y - halo, width: halo * 2, height: halo * 2)),
                             with: .color(.white.opacity(0.22 * depth * (1 - pulse))))
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.1, y: pt.y - 2.1, width: 4.2, height: 4.2)),
                             with: .color(.white.opacity(0.55 + 0.45 * depth)))
                }
            }
        }
        .background(Color.black)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: M.rCard, style: .continuous))
    }
}
