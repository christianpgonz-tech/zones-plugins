import AppKit
import SwiftUI

// Shared by the NFL Football, College Football and Soccer zones: one team picker with the same look and feel.
// Each zone compiles this file into its own bundle (see build.sh), so every zone is still a single download.

/// Geometry of the docked shape. The dial's centre is the point on the screen edge (or corner) the shape grows from.
/// `placement == "full"` means a whole circle in the middle of a window (used by the settings window).
struct FGeo {
    let placement: String
    let size: CGSize
    var full: Bool { placement == "full" }
    var isCorner: Bool { placement.hasPrefix("top") && placement != "top" || placement.hasPrefix("bottom") && placement != "bottom" }
    var radius: Double {
        if full { return min(size.width, size.height) / 2 }
        return (placement == "top" || placement == "bottom") ? size.height : size.width
    }
    var anchor: CGPoint {
        switch placement {
        case "full": CGPoint(x: size.width / 2, y: size.height / 2)
        case "top": CGPoint(x: size.width / 2, y: 0)
        case "bottom": CGPoint(x: size.width / 2, y: size.height)
        case "left": CGPoint(x: 0, y: size.height / 2)
        case "right": CGPoint(x: size.width, y: size.height / 2)
        case "topLeft": .zero
        case "topRight": CGPoint(x: size.width, y: 0)
        case "bottomLeft": CGPoint(x: 0, y: size.height)
        default: CGPoint(x: size.width, y: size.height)
        }
    }
    var span: Double { full ? 2 * .pi : (isCorner ? .pi / 2 : .pi) }
    /// The screen direction (y down) the visible part of the dial faces.
    var facing: Double {
        switch placement {
        case "top": .pi / 2
        case "bottom": -.pi / 2
        case "left": 0
        case "right": .pi
        case "topLeft": .pi / 4
        case "topRight": 3 * .pi / 4
        case "bottomLeft": -.pi / 4
        case "bottomRight": -3 * .pi / 4
        default: 0
        }
    }
    func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a)) }
    static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x <= -.pi { x += 2 * .pi }
        return x
    }

    /// The largest rectangle of the given proportions that fits inside the curved shape, and where it goes.
    /// `minStep` is how far from the anchor (as a fraction of radius) the box may start: 0.15 hugs the screen edge (the sports
    /// score cards want that), a larger value like 0.4 pushes the box further into the shape so it reads as more centered.
    func bestFit(design: CGSize, margin: CGFloat = 10, minStep: Double = 0.15) -> (scale: CGFloat, center: CGPoint) {
        var k: CGFloat = 3
        while k > 0.3 {
            let hw = design.width * k / 2, hh = design.height * k / 2
            for step in stride(from: minStep, through: 1.0, by: 0.02) {
                let c = point(radius * step, facing)
                let ok = [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)].allSatisfy { corner in
                    let p = CGPoint(x: c.x + corner.0 * hw, y: c.y + corner.1 * hh)
                    return hypot(p.x - anchor.x, p.y - anchor.y) <= radius * 0.93 && p.x >= margin && p.y >= margin && p.x <= size.width - margin && p.y <= size.height - margin
                }
                if ok { return (k, c) }
            }
            k -= 0.02
        }
        return (0.3, point(radius * max(minStep, 0.5), facing))
    }
}

/// Spin state shared by a dial: drag to turn, and it keeps coasting briefly after you let go.
final class DialSpin: ObservableObject {
    @Published var rotation: Double
    @Published var dragging = false
    @Published var hasRotated = false
    var omega = 0.0
    private var ticker: Timer?
    /// When given, remembers the turned position across the dial disappearing and reappearing (and app relaunches).
    private let persistKey: String?
    init(start: Double, persistKey: String? = nil) {
        self.persistKey = persistKey
        if let persistKey, UserDefaults.standard.object(forKey: persistKey) != nil {
            rotation = UserDefaults.standard.double(forKey: persistKey)
        } else {
            rotation = start
        }
    }
    func coast() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.dragging || abs(self.omega) < 0.01 { self.ticker?.invalidate(); self.ticker = nil; self.persist(); return }
            self.rotation += self.omega / 60; self.omega *= 0.94
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }
    func persist() { if let persistKey { UserDefaults.standard.set(rotation, forKey: persistKey) } }
}


/// Draws `text` letter by letter along a circle, upright to read (flipped on the lower half so it never runs upside down).
/// Shared by every dial that puts a group name on its rim (the sports team dials and the Converter's category dial).
func drawCurvedText(_ ctx: GraphicsContext, _ text: String, geo: FGeo, radius: Double, mid: Double, size: Double, weight: Font.Weight = .semibold, color: Color = .white) {
    let font = NSFont.systemFont(ofSize: size, weight: weight == .bold ? .bold : .semibold)
    let widths = text.map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width + 0.6 }
    let total = widths.reduce(0, +) / radius
    let below = sin(mid) > 0
    var cursor = below ? mid + total / 2 : mid - total / 2
    for (ch, w) in zip(text, widths) {
        let half = (w / radius) / 2
        let a = below ? cursor - half : cursor + half
        cursor += below ? -(w / radius) : (w / radius)
        var c = ctx
        let p = geo.point(radius, a)
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(below ? a - .pi / 2 : a + .pi / 2))
        c.draw(Text(String(ch)).font(.system(size: size, weight: weight)).foregroundColor(color), at: .zero)
    }
}

// MARK: - What a zone provides

struct PickerGroup: Identifiable, Hashable {
    let name: String            // "SEC", "Premier League", "NFC North"
    let short: String           // the form used when the full name won't fit its slice
    let color: Color
    var id: String { name }
}

protocol PickerTeam: Hashable {
    var pickKey: String { get }         // what is stored in favorites
    var pickAbbr: String { get }        // shown under a logo
    var pickName: String { get }        // "Alabama Crimson Tide"
    var pickShort: String { get }       // "Alabama"
    var pickGroup: String { get }       // the group's name
    var pickColor: Color { get }
    var pickSearchText: String { get }  // everything searchable: names, nickname, abbreviation
}

protocol PickerStore: ObservableObject {
    associatedtype Team: PickerTeam
    var pickTeams: [Team] { get }
    var pickGroups: [PickerGroup] { get }
    var pickRings: Int { get }
    var favorites: [String] { get set }
    var logoRevision: Int { get }
    var pickNoun: String { get }                       // "school", "club", "team"
    var pickExtraFilters: [(name: String, keys: Set<String>)] { get }
    func pickLogo(_ key: String) -> NSImage?
    func pickRank(_ key: String) -> Int?
    func pickSubtitle(_ key: String) -> String
    func pickNext(_ key: String) -> String?
    func pickOpen(_ key: String)
    func pickGroupLogo(_ group: String) -> NSImage?
    func pickGroupFlag(_ group: String) -> String?
}

extension PickerStore {
    func pickRank(_ key: String) -> Int? { nil }
    func pickGroupLogo(_ group: String) -> NSImage? { nil }
    func pickGroupFlag(_ group: String) -> String? { nil }
    var pickExtraFilters: [(name: String, keys: Set<String>)] { [] }
}

/// What the picker is showing: everything, one group, an extra list (like the Top 25), your own, or search results.
final class PickerState: ObservableObject {
    @Published var focus: String?          // nil = all; "group:X"; "extra:X"; "mine"
    @Published var query = ""
    @Published var searchActive = false    // the zone's search bar (the settings window has its own field)
    func reset() { focus = nil; query = ""; searchActive = false }
}

// MARK: - The dial

/// The team picker as a dial. Groups (conferences, leagues, divisions) are coloured sections around the rim; click a group's name to
/// open just that group as its own circle, or use the filter buttons and search. Click a team to add or remove it from your
/// favorites; double-click for its details.
struct SportsDial<S: PickerStore>: View {
    @ObservedObject var store: S
    @ObservedObject var state: PickerState
    @StateObject private var spin: DialSpin
    let geo: FGeo
    var onDone: (() -> Void)?
    @State private var hovered: S.Team?
    @State private var lastAngle: Double?
    @State private var lastTime = Date()
    @State private var travel: CGFloat = 0
    @State private var startPoint = CGPoint.zero
    @State private var lastTap: (key: String, time: Date)?
    @State private var pendingToggle: DispatchWorkItem?

    init(store: S, state: PickerState, geo: FGeo, onDone: (() -> Void)? = nil) {
        _store = ObservedObject(wrappedValue: store); _state = ObservedObject(wrappedValue: state)
        self.geo = geo; self.onDone = onDone
        _spin = StateObject(wrappedValue: DialSpin(start: geo.facing - geo.span / 2))
    }

    // Ring geometry: a hub, the team rings, and a thin rim band with the group names.
    private var hubRadius: Double { geo.radius * (geo.full ? 0.17 : 0.21) }
    private var teamInner: Double { geo.radius * (geo.full ? 0.19 : 0.235) }
    private var teamOuter: Double { geo.radius * 0.90 }
    private var labelOuter: Double { geo.radius * 0.995 }

    // MARK: Which teams, and where

    private static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
    /// The list shown as its own circle (nil = the full dial of everything).
    private var focusedList: (title: String, teams: [S.Team])? {
        let q = Self.fold(state.query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty {
            let scored: [(S.Team, Int)] = store.pickTeams.compactMap { t in
                let name = Self.fold(t.pickName), abbr = Self.fold(t.pickAbbr), short = Self.fold(t.pickShort), all = Self.fold(t.pickSearchText)
                if abbr == q || short == q { return (t, 0) }
                if short.hasPrefix(q) || name.hasPrefix(q) || abbr.hasPrefix(q) { return (t, 1) }
                if all.contains(q) { return (t, 2) }
                return nil
            }
            return ("“\(state.query)”", scored.sorted { ($0.1, $0.0.pickShort) < ($1.1, $1.0.pickShort) }.map(\.0))
        }
        guard let focus = state.focus else { return nil }
        if focus == "mine" { return ("My \(store.pickNoun)s", store.favorites.compactMap { k in store.pickTeams.first { $0.pickKey == k } }) }
        if focus.hasPrefix("group:") {
            let g = String(focus.dropFirst(6))
            return (g, store.pickTeams.filter { $0.pickGroup == g }.sorted { $0.pickShort < $1.pickShort })
        }
        if focus.hasPrefix("extra:"), let f = store.pickExtraFilters.first(where: { "extra:\($0.name)" == focus }) {
            return (f.name, store.pickTeams.filter { f.keys.contains($0.pickKey) }.sorted { $0.pickShort < $1.pickShort })
        }
        return nil
    }

    private struct Layout {
        var grid: [Int: S.Team] = [:]                       // column * 10 + ring
        var groups: [(name: String, short: String, color: Color, start: Int, columns: Int)] = []
        var columns = 0
        var rings = 1
        var focused = false
        var title = ""
    }
    private var layout: Layout {
        var l = Layout()
        if let f = focusedList {
            let n = f.teams.count
            l.focused = true; l.title = f.title
            l.rings = n <= 6 ? 2 : n <= 15 ? 3 : n <= 28 ? 4 : store.pickRings
            l.columns = max(1, (n + l.rings - 1) / l.rings)
            for (i, t) in f.teams.enumerated() { l.grid[(i / l.rings) * 10 + i % l.rings] = t }
            l.groups = [(f.title, f.title, Color.white.opacity(0.3), 0, l.columns)]
            return l
        }
        l.rings = store.pickRings
        for g in store.pickGroups {
            let list = store.pickTeams.filter { $0.pickGroup == g.name }.sorted { $0.pickShort < $1.pickShort }
            guard !list.isEmpty else { continue }
            let cols = (list.count + l.rings - 1) / l.rings
            for (i, t) in list.enumerated() { l.grid[(l.columns + i / l.rings) * 10 + i % l.rings] = t }
            l.groups.append((g.name, g.short, g.color, l.columns, cols))
            l.columns += cols
        }
        return l
    }
    private func rotation(_ l: Layout) -> Double { l.focused ? (geo.full ? -Double.pi / 2 : geo.facing - geo.span / 2) : spin.rotation }
    private func sector(_ l: Layout) -> Double { (l.focused ? geo.span : 2 * Double.pi) / Double(max(1, l.columns)) }
    private func ringThickness(_ l: Layout) -> Double { (teamOuter - teamInner) / Double(max(1, l.rings)) }

    // MARK: Body

    var body: some View {
        let _ = store.logoRevision
        let l = layout
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(ctx, l) }
            hub(l)
            if let team = hovered, !spin.dragging { hoverCard(team, l).position(cardPosition(team, l)).allowsHitTesting(false) }
        }
        .background(KeyCatcher(active: { state.searchActive }, onKey: handleKey))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                hovered = team(at: p, l)
                if geo.full || l.focused { (hovered != nil || group(at: p, l) != nil ? NSCursor.pointingHand : NSCursor.arrow).set() }
                else if spin.dragging { NSCursor.closedHand.set() } else if onDial(p) { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            case .ended:
                hovered = nil; if !spin.dragging { NSCursor.arrow.set() }
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let angle = atan2(value.location.y - geo.anchor.y, value.location.x - geo.anchor.x)
                if lastAngle == nil { lastAngle = angle; lastTime = Date(); travel = 0; startPoint = value.location; spin.omega = 0 }
                travel = max(travel, hypot(value.location.x - startPoint.x, value.location.y - startPoint.y))
                guard !geo.full, !l.focused, travel > 4, let previous = lastAngle else { return }
                spin.dragging = true; spin.hasRotated = true
                NSCursor.closedHand.set()
                let delta = FGeo.wrap(angle - previous)
                let now = Date(), dt = max(0.001, now.timeIntervalSince(lastTime))
                spin.rotation += delta
                spin.omega = spin.omega * 0.6 + (delta / dt) * 0.4
                lastAngle = angle; lastTime = now
            }
            .onEnded { value in
                let wasDrag = spin.dragging
                lastAngle = nil; spin.dragging = false
                if wasDrag { spin.omega = max(-9, min(9, spin.omega)); spin.coast(); return }
                guard travel <= 6 else { return }
                if let t = team(at: value.location, l) { tapped(t) }
                else if !l.focused, let g = group(at: value.location, l) { state.focus = "group:\(g)"; state.query = "" }
            })
    }

    // MARK: Keyboard (the zone's search)

    private func handleKey(_ key: String) {
        switch key {
        case "⎋": if !state.query.isEmpty { state.query = "" } else if state.focus != nil { state.focus = nil } else { state.searchActive = false }
        case "⌫": if !state.query.isEmpty { state.query.removeLast() }
        case "↩": if let first = focusedList?.teams.first { toggleKey(first.pickKey) }
        default: if state.query.count < 24 { state.query += key }
        }
    }

    // MARK: Taps

    /// One click adds or removes a favorite (after a beat, so a double-click doesn't do it twice); a double-click opens the details.
    private func tapped(_ team: S.Team) {
        let key = team.pickKey
        if let last = lastTap, last.key == key, Date().timeIntervalSince(last.time) < 0.35 {
            pendingToggle?.cancel(); lastTap = nil
            store.pickOpen(key)
        } else {
            lastTap = (key, Date())
            let work = DispatchWorkItem { toggleKey(key) }
            pendingToggle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    private func toggleKey(_ key: String) {
        if let i = store.favorites.firstIndex(of: key) { store.favorites.remove(at: i) } else { store.favorites.append(key) }
    }

    // MARK: Hit testing

    private func onDial(_ p: CGPoint) -> Bool {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        return r >= hubRadius && r <= geo.radius
    }
    private func angleIndex(_ p: CGPoint, _ l: Layout) -> Int? {
        var local = atan2(p.y - geo.anchor.y, p.x - geo.anchor.x) - rotation(l)
        local = local.truncatingRemainder(dividingBy: 2 * .pi)
        if local < 0 { local += 2 * .pi }
        if l.focused && local >= geo.span && !geo.full { return nil }
        return min(Int(local / sector(l)), max(0, l.columns - 1))
    }
    private func team(at p: CGPoint, _ l: Layout) -> S.Team? {
        guard l.columns > 0 else { return nil }
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        let ring = Int(floor((r - teamInner) / ringThickness(l)))
        guard ring >= 0, ring < l.rings, let col = angleIndex(p, l) else { return nil }
        return l.grid[col * 10 + ring]
    }
    private func group(at p: CGPoint, _ l: Layout) -> String? {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        guard r > teamOuter, r <= labelOuter + 4, let col = angleIndex(p, l) else { return nil }
        return l.groups.first { col >= $0.start && col < $0.start + $0.columns }?.name
    }

    // MARK: Drawing

    private func tilePath(_ r0: Double, _ r1: Double, _ a0: Double, _ a1: Double, grow: Double = 1) -> Path {
        let g0 = 1.5 / r0, g1 = 1.5 / r1
        var pts: [CGPoint] = []
        let n = max(6, Int(ceil((a1 - a0) / (2 * .pi / 240))))   // about 1.5° per segment, so wide arcs (the rim bands) stay perfectly round
        for i in 0...n { pts.append(geo.point(r1 - 1.5, a0 + g1 + (a1 - a0 - 2 * g1) * Double(i) / Double(n))) }
        for i in stride(from: n, through: 0, by: -1) { pts.append(geo.point(r0 + 1.5, a0 + g0 + (a1 - a0 - 2 * g0) * Double(i) / Double(n))) }
        if grow != 1 {
            let c = geo.point((r0 + r1) / 2, (a0 + a1) / 2)
            pts = pts.map { CGPoint(x: c.x + ($0.x - c.x) * grow, y: c.y + ($0.y - c.y) * grow) }
        }
        var p = Path(); p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
        return p
    }
    private func visible(_ mid: Double, _ sector: Double, _ l: Layout) -> Bool { geo.full || l.focused || abs(FGeo.wrap(mid - geo.facing)) <= geo.span / 2 + sector / 2 }

    private func draw(_ ctx: GraphicsContext, _ l: Layout) {
        guard l.columns > 0 else { return }
        let sec = sector(l), rot = rotation(l), thick = ringThickness(l)
        var hoveredDraw: (team: S.Team, r0: Double, r1: Double, a0: Double, a1: Double)?
        for key in l.grid.keys {
            let col = key / 10, ring = key % 10
            guard let team = l.grid[key] else { continue }
            let a0 = rot + Double(col) * sec, a1 = a0 + sec
            guard visible((a0 + a1) / 2, sec, l) else { continue }
            let r0 = teamInner + Double(ring) * thick, r1 = r0 + thick
            let path = tilePath(r0, r1, a0, a1)
            ctx.fill(path, with: .color(team.pickColor))
            drawContent(ctx, team: team, r0: r0, r1: r1, a0: a0, a1: a1, clip: path, showName: l.focused)
            if store.favorites.contains(team.pickKey) { ctx.stroke(path, with: .color(Color(red: 1, green: 0.84, blue: 0.04)), lineWidth: 3) }
            if hovered == team && !spin.dragging { hoveredDraw = (team, r0, r1, a0, a1) }
        }
        // Group names on the rim, following the arc
        for g in l.groups {
            let a0 = rot + Double(g.start) * sec, a1 = rot + Double(g.start + g.columns) * sec
            guard visible((a0 + a1) / 2, sec * Double(g.columns), l) else { continue }
            ctx.fill(tilePath(teamOuter + 2, labelOuter, a0, a1), with: .color(g.color.opacity(0.85)))
            drawRimLabel(ctx, g.name, short: g.short, arc: a1 - a0, mid: (a0 + a1) / 2)
        }
        if let h = hoveredDraw {
            let big = tilePath(h.r0, h.r1, h.a0, h.a1, grow: 1.22)
            var lifted = ctx
            lifted.addFilter(.shadow(color: .black.opacity(0.55), radius: 9, x: 0, y: 4))
            lifted.fill(big, with: .color(h.team.pickColor))
            ctx.stroke(big, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            drawContent(ctx, team: h.team, r0: h.r0, r1: h.r1, a0: h.a0, a1: h.a1, scale: 1.22, clip: big, showName: true)
        }
    }

    /// The group's name along the rim, with its logo and flag either side when the zone has them.
    private func drawRimLabel(_ ctx: GraphicsContext, _ name: String, short: String, arc: Double, mid: Double) {
        let band = labelOuter - teamOuter
        let r = (teamOuter + labelOuter) / 2 + 1
        let size = max(8, min(13, band * 0.5))
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        func length(_ t: String) -> Double { t.map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width + 0.6 }.reduce(0, +) / r }
        let logo = store.pickGroupLogo(name), flag = store.pickGroupFlag(name)
        let badge = band * 0.86, extra = (logo != nil ? badge / r + 0.03 : 0) + (flag != nil ? badge / r + 0.03 : 0)
        var text = name
        if length(text) + extra > arc * 0.94 { text = short }
        if length(text) + extra > arc * 0.94 { text = String(text.prefix(4)) }
        drawCurvedText(ctx, text, geo: geo, radius: r, mid: mid, size: size)
        let total = length(text)
        let below = sin(mid) > 0
        let sign = below ? -1.0 : 1.0                     // the direction the text reads along the arc
        let pad = 0.02 + (badge / 2) / r
        if logo != nil || flag != nil, extra < arc * 0.94 {
            if let logo {
                let lc = geo.point(r, mid - sign * (total / 2 + pad))
                let disc = CGRect(x: lc.x - badge / 2, y: lc.y - badge / 2, width: badge, height: badge)
                ctx.fill(Path(ellipseIn: disc), with: .color(.white.opacity(0.93)))
                ctx.draw(ctx.resolve(Image(nsImage: logo)), in: disc.insetBy(dx: badge * 0.1, dy: badge * 0.1))
            }
            if let flag {
                let fa = mid + sign * (total / 2 + pad)
                var f = ctx
                let fc = geo.point(r, fa)
                f.translateBy(x: fc.x, y: fc.y); f.rotate(by: .radians(below ? fa - .pi / 2 : fa + .pi / 2))
                f.draw(Text(flag).font(.system(size: badge * 0.95)), at: .zero)
            }
        }
    }



    /// Is this screen point inside the tile (with a small safety margin)?
    private func inside(_ p: CGPoint, r0: Double, r1: Double, a0: Double, a1: Double) -> Bool {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        guard r >= r0 + 3, r <= r1 - 3 else { return false }
        let half = (a1 - a0) / 2, mid = (a0 + a1) / 2
        let d = abs(FGeo.wrap(atan2(p.y - geo.anchor.y, p.x - geo.anchor.x) - mid))
        return d <= half - 2.5 / max(r, 1)
    }
    /// The largest box of the given shape (width = ratio x height) centred on the tile that stays inside it.
    private func fittedHeight(center: CGPoint, ratio: Double, r0: Double, r1: Double, a0: Double, a1: Double, maxHeight: Double) -> Double {
        var h = maxHeight
        while h > 10 {
            let hw = h * ratio / 2, hh = h / 2
            let ok = [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)].allSatisfy { c in inside(CGPoint(x: center.x + c.0 * hw, y: center.y + c.1 * hh), r0: r0, r1: r1, a0: a0, a1: a1) }
            if ok { return h }
            h -= 2
        }
        return 0
    }

    private func drawContent(_ context: GraphicsContext, team: S.Team, r0: Double, r1: Double, a0: Double, a1: Double, scale: Double = 1, clip: Path, showName: Bool) {
        var ctx = context
        ctx.clip(to: clip)
        let rm = (r0 + r1) / 2, mid = (a0 + a1) / 2
        let center = geo.point(rm, mid)
        // Text stays upright, so fit real boxes inside the (possibly tilted) tile instead of guessing.
        let wideH = fittedHeight(center: center, ratio: 2.7, r0: r0, r1: r1, a0: a0, a1: a1, maxHeight: 66)
        if wideH >= 30 {
            let h = wideH * scale, w = h * 2.7
            let logoSize = min(h * 0.96, 62 * scale)
            let logoCenter = CGPoint(x: center.x - w / 2 + logoSize / 2, y: center.y)
            drawLogo(ctx, team, at: logoCenter, size: logoSize)
            let textX = logoCenter.x + logoSize / 2 + 5
            let avail = w - logoSize - 8
            let fontSize = max(8, min(11.5 * scale, 11.5 * scale * avail / (Double(team.pickShort.count) * 6.4)))
            let rank = store.pickRank(team.pickKey).map { "#\($0) " } ?? ""
            ctx.draw(Text(rank + team.pickShort).font(.system(size: fontSize, weight: .bold)).foregroundColor(.white), at: CGPoint(x: textX, y: center.y), anchor: .leading)
        } else {
            // A logo with its abbreviation underneath, in the biggest box that fits.
            let h = fittedHeight(center: center, ratio: 0.78, r0: r0, r1: r1, a0: a0, a1: a1, maxHeight: 64)
            let box = max(h, 14) * scale
            let withLabel = box >= 34
            let logoSize = withLabel ? box * 0.72 : box * 0.95
            drawLogo(ctx, team, at: CGPoint(x: center.x, y: center.y - (withLabel ? box * 0.13 : 0)), size: logoSize)
            if withLabel { ctx.draw(Text(team.pickAbbr).font(.system(size: max(7, min(10, box * 0.2)), weight: .bold)).foregroundColor(.white), at: CGPoint(x: center.x, y: center.y + box * 0.4)) }
        }
    }
    private func drawLogo(_ ctx: GraphicsContext, _ team: S.Team, at c: CGPoint, size: Double) {
        let rect = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
        ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.93)))
        if let image = store.pickLogo(team.pickKey) {
            ctx.draw(ctx.resolve(Image(nsImage: image)), in: rect.insetBy(dx: size * 0.09, dy: size * 0.09))
        } else {
            ctx.draw(Text(team.pickAbbr).font(.system(size: size * 0.3, weight: .heavy)).foregroundColor(team.pickColor), at: c)
        }
    }

    // MARK: Hub, search bar and hover card

    private func hub(_ l: Layout) -> some View {
        // The block sits against the screen edge (or corner) the zone grows from, so nothing is ever cut off.
        let alignment: Alignment
        switch geo.placement {
        case "top": alignment = .top
        case "bottom": alignment = .bottom
        case "left": alignment = .leading
        case "right": alignment = .trailing
        case "topLeft": alignment = .topLeading
        case "topRight": alignment = .topTrailing
        case "bottomLeft": alignment = .bottomLeading
        case "bottomRight": alignment = .bottomTrailing
        default: alignment = .center
        }
        return VStack(spacing: 4) {
            if state.searchActive && !geo.full {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                    Text(state.query.isEmpty ? "Type to search" : state.query).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Button { state.query = ""; state.searchActive = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain)
                }.padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.black.opacity(0.55)))
            }
            if l.focused {
                Button { state.focus = nil; state.query = "" } label: {
                    Label("All", systemImage: "chevron.left").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.primary.opacity(0.2)))
                }.buttonStyle(.plain)
                if !geo.isCorner { Text("\(l.title) · \(l.grid.count)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            } else if !geo.full && !spin.hasRotated && !geo.isCorner && !state.searchActive {
                Image(systemName: "hand.draw").font(.system(size: 13)); Text("Drag to rotate").font(.system(size: 10, weight: .medium))
            }
            if geo.full { Text("\(store.favorites.count) picked").font(.system(size: 11)).foregroundStyle(.secondary) }
            if l.focused && l.grid.isEmpty { Text("Nothing matches").font(.system(size: 10)).foregroundStyle(.secondary) }
            if let onDone {
                HStack(spacing: 6) {
                    Button { state.searchActive.toggle(); if !state.searchActive { state.query = "" } } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).padding(6).background(Circle().fill(Color.primary.opacity(state.searchActive ? 0.35 : 0.2)))
                    }.buttonStyle(.plain).help("Search")
                    Button(action: onDone) { Label("Done · \(store.favorites.count)", systemImage: "checkmark").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.primary.opacity(0.2))) }.buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.primary).fixedSize()
        .padding(geo.full ? 0 : 6)
        .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
    }

    private func cardPosition(_ team: S.Team, _ l: Layout) -> CGPoint {
        let entry = l.grid.first { $0.value == team }?.key ?? 0
        let tile = geo.point(teamInner + (Double(entry % 10) + 0.5) * ringThickness(l), rotation(l) + (Double(entry / 10) + 0.5) * sector(l))
        let toward = geo.point(geo.radius * 0.5, geo.facing)
        let dx = toward.x - tile.x, dy = toward.y - tile.y, len = max(1, hypot(dx, dy))
        let s = max(1, geo.radius / 300), hw = 125 * s, hh = 52 * s
        var c = CGPoint(x: tile.x + dx / len * (hw * 0.9 + 30), y: tile.y + dy / len * (hh + 30))
        c.x = min(max(c.x, hw + 6), max(hw + 6, geo.size.width - hw - 6)); c.y = min(max(c.y, hh + 6), max(hh + 6, geo.size.height - hh - 6))
        return c
    }

    private func hoverCard(_ team: S.Team, _ l: Layout) -> some View {
        HStack(spacing: 10) {
            PickerLogo(store: store, team: team, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let r = store.pickRank(team.pickKey) { Text("#\(r)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.secondary) }
                    Text(team.pickName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                Text(store.pickSubtitle(team.pickKey)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if let next = store.pickNext(team.pickKey) { Text(next).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                Text(store.favorites.contains(team.pickKey) ? "Click to remove · double-click for details" : "Click to add · double-click for details").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(10).frame(width: 275, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.18)))
        .shadow(radius: 8)
        .scaleEffect(max(1, geo.radius / 300) * 0.95)
    }
}

/// A team's logo on a light disc (or its colours and abbreviation if the logo isn't available), for the picker's hover card.
struct PickerLogo<S: PickerStore>: View {
    @ObservedObject var store: S
    let team: S.Team
    var size: CGFloat = 40
    var body: some View {
        let _ = store.logoRevision
        if let image = store.pickLogo(team.pickKey) {
            ZStack { Circle().fill(Color.white.opacity(0.93)); Image(nsImage: image).resizable().scaledToFit().frame(width: size * 0.82, height: size * 0.82) }.frame(width: size, height: size)
        } else {
            ZStack { Circle().fill(team.pickColor); Text(team.pickAbbr).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.4).lineLimit(1) }.frame(width: size, height: size)
        }
    }
}

// MARK: - Search and filter bar (settings windows)

/// The same search box and filter buttons at the top of every zone's settings window.
struct PickerToolbar<S: PickerStore>: View {
    @ObservedObject var store: S
    @ObservedObject var state: PickerState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search a \(store.pickNoun) by name, nickname or abbreviation", text: $state.query).textFieldStyle(.plain)
                    if !state.query.isEmpty { Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 8).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                Text("\(store.favorites.count) picked").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", nil)
                    chip("My \(store.pickNoun)s", "mine")
                    ForEach(store.pickExtraFilters, id: \.name) { chip($0.name, "extra:\($0.name)") }
                    ForEach(store.pickGroups) { chip($0.short, "group:\($0.name)") }
                }
            }
        }
    }
    private func chip(_ title: String, _ focus: String?) -> some View {
        let on = state.query.isEmpty && state.focus == focus
        return Button { state.focus = focus; state.query = "" } label: {
            Text(title).font(.callout.weight(on ? .semibold : .regular)).lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(on ? 0.22 : 0.07)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Typing in the zone

/// Lets the zone's search bar take typing. A click on the zone makes its panel the key window; after that, letters, digits,
/// Delete, Return and Escape go to the search.
struct KeyCatcher: NSViewRepresentable {
    let active: () -> Bool
    let onKey: (String) -> Void
    func makeNSView(context: Context) -> KeyCatcherView { let v = KeyCatcherView(); v.active = active; v.onKey = onKey; return v }
    func updateNSView(_ v: KeyCatcherView, context: Context) { v.active = active; v.onKey = onKey }
}
final class KeyCatcherView: NSView {
    var active: () -> Bool = { false }
    var onKey: (String) -> Void = { _ in }
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window, self.active() else { return event }
            if event.type == .leftMouseDown { if !window.isKeyWindow { window.makeKey() }; return event }
            guard window.isKeyWindow else { return event }
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            switch event.keyCode {
            case 53: self.onKey("⎋"); return nil
            case 51, 117: self.onKey("⌫"); return nil
            case 36, 76: self.onKey("↩"); return nil
            default: break
            }
            guard let c = event.characters, c.count == 1, let scalar = c.unicodeScalars.first,
                  CharacterSet.alphanumerics.contains(scalar) || c == " " || c == "-" || c == "'" || c == "." else { return event }
            self.onKey(c)
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

// MARK: - The name badge (NFL Football and College Football)

/// The zone's name in white, with its icon first and centred on the same line. Both football zones use this one view and one
/// placement rule, so the size, the font and the position are identical; only the icon and the words differ.
struct SportBadge<Icon: View>: View {
    let title: String
    let size: CGFloat
    @ViewBuilder var icon: Icon
    var body: some View {
        HStack(alignment: .center, spacing: size * 0.25) {
            icon.foregroundStyle(.white).frame(width: size * 1.05, height: size * 1.05)
            Text(title).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
        }.shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

enum SportBadgeLayout {
    /// The longest badge name; every zone is fitted with it, so all of them get the same size.
    static var reference = "College Football"
    static func width(size: CGFloat) -> CGFloat { size * 1.05 + size * 0.25 + CGFloat(reference.count) * size * 0.29 }

    /// Half circles: the tip of the circle, centred on the middle line. Corners: centred just under the card (above it if there's no room).
    static func spot(geo: FGeo, rect: CGRect) -> (size: CGFloat, center: CGPoint)? {
        var size = max(22, min(40, rect.width * 0.095))
        let keepOut = rect.insetBy(dx: -4, dy: -4)
        func fits(_ box: CGRect, _ limit: Double) -> Bool {
            !box.intersects(keepOut) && [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)].allSatisfy { p in
                hypot(p.0 - geo.anchor.x, p.1 - geo.anchor.y) <= geo.radius * limit && p.0 >= 4 && p.1 >= 4 && p.0 <= geo.size.width - 4 && p.1 <= geo.size.height - 4
            }
        }
        for _ in 0..<5 {
            let w = width(size: size), h = size * 1.05 + 6
            if !geo.isCorner && !geo.full {
                let dir = CGPoint(x: cos(geo.facing), y: sin(geo.facing))
                let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
                let far = corners.map { ($0.x - geo.anchor.x) * dir.x + ($0.y - geo.anchor.y) * dir.y }.max() ?? 0
                var d = geo.radius * 0.97 - h / 2
                while d >= far + h / 2 + 2 {
                    let c = CGPoint(x: geo.anchor.x + dir.x * d, y: geo.anchor.y + dir.y * d)
                    if fits(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), 0.955) { return (size, c) }
                    d -= 3
                }
            } else {
                let gap = size * 0.45
                for y in [rect.maxY + gap + h / 2, rect.minY - gap - h / 2] {
                    let c = CGPoint(x: rect.midX, y: y)
                    if fits(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), 0.95) { return (size, c) }
                }
            }
            size *= 0.9
        }
        return nil
    }
}
