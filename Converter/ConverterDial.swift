import AppKit
import SwiftUI

/// A circle of a fixed radius around an absolute point — unlike `Circle()`, which sizes itself to whatever frame it's
/// given, this ignores the view's own bounding rect entirely, for defining a hit-testable region smaller than a view's
/// full frame at an exact radius from the dial's anchor.
private struct HitDisc: Shape {
    let center: CGPoint
    let radius: Double
    func path(in rect: CGRect) -> Path { Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)) }
}

/// One slice of a dial: a category, or a saved favorite pair.
struct DialItem: Identifiable, Hashable {
    let id: String
    let lines: [String]         // one to three short lines of text
    let symbol: String?         // SF symbol drawn above the text
    var hasFavorite: Bool = false   // a small star badge — this category has at least one favorited unit inside it
}

/// A named cluster of slices, drawn together with its name curved along the rim (like a sports dial's conference section).
/// An empty name draws no rim label — used for the ungrouped Favorites slice and for the favorite-pairs dial.
struct DialSection: Identifiable {
    let name: String
    let items: [DialItem]
    var id: String { name.isEmpty ? "•" : name }
}

/// A dial of slices in rings, grouped into named rim-labelled sections, drawn on the zone's curved shape. If there are
/// more columns than fit at once, drag to turn it (as the sports team dials do).
struct RingDial: View {
    let sections: [DialSection]
    let geo: FGeo
    let rings: Int
    let onPick: (String) -> Void
    @StateObject private var spin: DialSpin
    @State private var hovered: String?
    @State private var lastAngle: Double?
    @State private var travel: CGFloat = 0
    @State private var startPoint = CGPoint.zero

    /// `persistKey`, when given, remembers this dial's turned position (in UserDefaults) so leaving for a category and
    /// coming back — or quitting and relaunching — finds the wheel where it was left, instead of resetting to the start.
    init(sections: [DialSection], geo: FGeo, rings: Int, persistKey: String? = nil, onPick: @escaping (String) -> Void) {
        self.sections = sections; self.geo = geo; self.rings = rings; self.onPick = onPick
        _spin = StateObject(wrappedValue: DialSpin(start: geo.facing - geo.span / 2, persistKey: persistKey))
    }

    private var hasLabels: Bool { sections.contains { !$0.name.isEmpty } }
    private var hubRadius: Double { geo.radius * 0.2 }
    private var inner: Double { geo.radius * 0.23 }
    private var outer: Double { geo.radius * (hasLabels ? 0.83 : 0.94) }
    private var labelOuter: Double { geo.radius * 0.97 }

    private struct Layout {
        var grid: [Int: DialItem] = [:]                                        // column * 10 + ring
        var colCount: [Int: Int] = [:]                                         // how many items actually sit in each column
        var colGroup: [Int: Int] = [:]                                        // which section (by index) each column belongs to
        var groups: [(name: String, start: Int, columns: Int)] = []
        var columns = 0
    }
    /// The last column of a section is often only partly filled (e.g. a lone Favorites slice, or 7 items over 2 rings).
    /// Rather than leave the empty ring blank, that column's items are stretched to fill the whole radial band.
    private var layout: Layout {
        var l = Layout()
        for (gi, section) in sections.enumerated() {
            let n = section.items.count
            guard n > 0 else { continue }
            let cols = (n + rings - 1) / rings
            for (i, item) in section.items.enumerated() {
                let col = l.columns + i / rings
                l.grid[col * 10 + i % rings] = item
                l.colCount[col, default: 0] += 1
                l.colGroup[col] = gi
            }
            l.groups.append((section.name, l.columns, cols))
            l.columns += cols
        }
        return l
    }
    /// One muted hue per group (low saturation, the same dark family the rest of the zone uses), so it's obvious at a
    /// glance where one group ends and the next begins — without going back to a rainbow of per-category colors.
    private static let groupHues: [Double] = [0.62, 0.79, 0.95, 0.12, 0.29, 0.46]
    private func groupHue(_ l: Layout, _ col: Int) -> Double { Self.groupHues[(l.colGroup[col] ?? 0) % Self.groupHues.count] }
    private var visible: Int { geo.full ? 12 : geo.isCorner ? 3 : 6 }
    private var turns: Bool { layout.columns > visible }
    // While turning, the columns spin freely all the way around a full 2π — so their sector width must divide evenly into
    // a full circle (2π / total columns), not the visible arc alone. Using the visible arc's own width here (the previous
    // bug) meant the columns' combined width didn't add up to exactly 2π, so far enough around the drag, a later column
    // would land back on top of an earlier one — which is exactly what put Media's "Print Resolution" at the same angle
    // as Everyday's "Length", not a miscategorization.
    private var sector: Double { (turns ? 2 * Double.pi / Double(max(1, layout.columns)) : geo.span / Double(max(1, layout.columns))) }
    private var rotation: Double { turns ? spin.rotation : geo.facing - geo.span / 2 }
    private func thickness(_ col: Int, _ l: Layout) -> Double { (outer - inner) / Double(max(1, l.colCount[col] ?? rings)) }

    private func item(at p: CGPoint, _ l: Layout) -> DialItem? {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        guard r >= inner, r <= outer else { return nil }
        var local = atan2(p.y - geo.anchor.y, p.x - geo.anchor.x) - rotation
        local = local.truncatingRemainder(dividingBy: 2 * .pi); if local < 0 { local += 2 * .pi }
        if !turns && local > geo.span { return nil }
        let col = Int(local / sector)
        guard col < l.columns else { return nil }
        let th = thickness(col, l)
        let ring = min((l.colCount[col] ?? rings) - 1, Int((r - inner) / th))
        return l.grid[col * 10 + ring]
    }

    var body: some View {
        let l = layout
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(ctx, l) }
            Circle().fill(Color.black.opacity(0.35)).frame(width: hubRadius * 2, height: hubRadius * 2).position(geo.anchor).allowsHitTesting(false)
        }
        // Out to `labelOuter`, not just `outer` — the band between them is the curved rim label (a group name like
        // "Everyday"). Holding it has to turn the wheel too, the same as holding an actual slice does, so the shape
        // has to include it. Reposition-dragging the zone itself still works from anywhere outside this whole disc.
        .contentShape(HitDisc(center: geo.anchor, radius: labelOuter))
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hovered = item(at: p, l)?.id; (hovered != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
            case .ended: hovered = nil; NSCursor.arrow.set()
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let angle = atan2(value.location.y - geo.anchor.y, value.location.x - geo.anchor.x)
                if lastAngle == nil { lastAngle = angle; travel = 0; startPoint = value.location; spin.omega = 0 }
                travel = max(travel, hypot(value.location.x - startPoint.x, value.location.y - startPoint.y))
                guard turns, travel > 4, let previous = lastAngle else { return }
                spin.dragging = true
                spin.rotation += FGeo.wrap(angle - previous)
                lastAngle = angle
            }
            .onEnded { value in
                let wasDrag = spin.dragging
                lastAngle = nil; spin.dragging = false
                if wasDrag { spin.persist(); return }
                guard travel <= 6, let it = item(at: value.location, l) else { return }
                onPick(it.id)
            })
    }

    // MARK: Drawing

    private func wedge(_ r0: Double, _ r1: Double, _ a0: Double, _ a1: Double) -> Path {
        var p = Path(); let n = max(6, Int((a1 - a0) / 0.05))
        for i in 0...n { let pt = geo.point(r1, a0 + (a1 - a0) * Double(i) / Double(n)); if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
        for i in stride(from: n, through: 0, by: -1) { p.addLine(to: geo.point(r0, a0 + (a1 - a0) * Double(i) / Double(n))) }
        p.closeSubpath(); return p
    }
    /// Is this slice's middle angle currently within the visible span (matters only while turning)?
    private func onScreen(_ mid: Double) -> Bool { !turns || abs(FGeo.wrap(mid - geo.facing)) <= geo.span / 2 + sector / 2 }

    private func draw(_ ctx: GraphicsContext, _ l: Layout) {
        guard l.columns > 0 else { return }
        for key in l.grid.keys {
            let col = key / 10, ring = key % 10
            guard let it = l.grid[key] else { continue }
            let a0 = rotation + Double(col) * sector, a1 = a0 + sector
            guard onScreen((a0 + a1) / 2) else { continue }
            let th = thickness(col, l)
            let r0 = inner + Double(ring) * th + 1.5, r1 = inner + Double(ring + 1) * th - 1.5
            drawSlice(ctx, it, r0: r0, r1: max(r0 + 1, r1), a0: a0 + 0.012, a1: a1 - 0.012, hue: groupHue(l, col), hot: hovered == it.id)
        }
        // Group names on the rim, following the arc, each in its own group's hue.
        if hasLabels {
            for (i, g) in l.groups.enumerated() where !g.name.isEmpty {
                let a0 = rotation + Double(g.start) * sector, a1 = rotation + Double(g.start + g.columns) * sector
                guard onScreen((a0 + a1) / 2) else { continue }
                let band = Color(hue: Self.groupHues[i % Self.groupHues.count], saturation: 0.3, brightness: 0.42)
                ctx.fill(wedge(outer + 2, labelOuter, a0, a1), with: .color(band))
                drawRimLabel(ctx, g.name, arc: a1 - a0, mid: (a0 + a1) / 2)
            }
        }
        // A drag hint at each visible edge when there's more than fits on screen.
        if turns {
            drawDragHint(ctx, at: geo.facing - geo.span / 2, pointing: -1)
            drawDragHint(ctx, at: geo.facing + geo.span / 2, pointing: 1)
        }
    }

    /// The real rendered width of `text` at a given size — measuring (rather than guessing from character count) is what
    /// keeps a slice's icon and words from spilling into its neighbor, at any zone size from the smallest to the largest.
    private func measuredWidth(_ text: String, _ size: Double, _ weight: NSFont.Weight) -> Double {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
    }
    private func drawSlice(_ ctx: GraphicsContext, _ item: DialItem, r0: Double, r1: Double, a0: Double, a1: Double, hue: Double, hot: Bool) {
        let path = wedge(r0, r1, a0, a1)
        // One muted hue per group, with just an alternating shade within it — enough to tell groups apart at a glance,
        // without turning back into a rainbow of individual category colors.
        let alt = Int(((a0 + a1) / 2) / max(sector, 0.001)) % 2 == 0
        ctx.fill(path, with: .color(Color(hue: hue, saturation: hot ? 0.32 : 0.24, brightness: hot ? 0.46 : (alt ? 0.34 : 0.29))))
        ctx.stroke(path, with: .color(.white.opacity(hot ? 0.9 : 0.16)), lineWidth: hot ? 2 : 1)
        let mid = (a0 + a1) / 2, rm = (r0 + r1) / 2
        let c = geo.point(rm, mid)
        guard c.x > -20, c.x < geo.size.width + 20, c.y > -20, c.y < geo.size.height + 20 else { return }
        // The narrowest point of the wedge (its inner edge) is the true limit — using the midpoint instead let text spill
        // past the wedge into whatever's next door on bigger zones or tighter corners.
        let width = max(10, r0 * (a1 - a0) * 0.92)
        // A column with fewer items than `rings` gets stretched to fill the whole radial band rather than leaving an
        // empty gap (see `thickness(_:_:)`) — good for the wedge itself, but sizing text/icon off that stretched height
        // made a slice in a half-empty column (like Media dropping to 2 items after Color was removed) render its label
        // noticeably larger than every other slice. Size off the *normal* per-ring height instead, so the wedge still
        // visually fills the gap but its label matches every other slice's size regardless of how full its column is.
        let normalHeight = (outer - inner) / Double(max(1, rings)) * 0.92
        let height = min((r1 - r0) * 0.92, normalHeight)
        var lines = item.lines
        var fontSize = min(18.0, height * 0.22)
        while fontSize > 6 {
            let widest = lines.map { measuredWidth($0, fontSize, .semibold) }.max() ?? 0
            if widest <= width { break }
            fontSize -= 0.5
        }
        if fontSize <= 6.5, lines.count > 1 {
            // Still too tight for every line: keep just the first word and re-fit from scratch rather than render at an illegible size.
            lines = [lines[0]]
            fontSize = min(18.0, height * 0.3)
            while fontSize > 6, measuredWidth(lines[0], fontSize, .semibold) > width { fontSize -= 0.5 }
        }
        fontSize = max(6, fontSize)
        var iconSize = min(height * 0.34, 30.0)
        var iconImg: (image: GraphicsContext.ResolvedImage, drawWidth: Double)?
        if let s = item.symbol {
            var img = ctx.resolve(Image(systemName: s))
            img.shading = .color(.white)
            // Some symbols (the ruler, especially) are much wider than tall — scaling only to a target height can still
            // draw wider than the wedge itself. Check both dimensions and shrink to whichever is tighter.
            if img.size.height > 0, img.size.width > 0 {
                let byHeight = iconSize / img.size.height
                if img.size.width * byHeight > width { iconSize = width / img.size.width * img.size.height }
            }
            let ratio = img.size.height > 0 ? iconSize / img.size.height : 1
            iconImg = (img, img.size.width * ratio)
        }
        let blockH = (iconImg != nil ? iconSize + 4 : 0) + Double(lines.count) * (fontSize + 3)
        var y = c.y - blockH / 2
        if let (img, drawWidth) = iconImg {
            ctx.draw(img, in: CGRect(x: c.x - drawWidth / 2, y: y, width: drawWidth, height: iconSize))
            y += iconSize + 4
        }
        // Every line here is a wrapped piece of the same one name ("Shoe" / "Size"), not a title and a subtitle, so they
        // all get the same weight — mixing bold and regular made a single name read like two different things.
        for line in lines {
            ctx.draw(ctx.resolve(Text(line).font(.system(size: fontSize, weight: .semibold)).foregroundColor(.white)), at: CGPoint(x: c.x, y: y + (fontSize + 3) / 2))
            y += fontSize + 3
        }
        // A small star toward one edge of the slice: this category already has a favorited unit inside it. Positioned in
        // polar terms (an angle and radius within this same wedge), not a Cartesian corner offset, so it stays inside the
        // wedge's own rotated shape instead of drifting into whichever neighbor happens to sit in that direction on screen.
        if item.hasFavorite {
            let starAngle = mid + (a1 - a0) * 0.3, starR = r1 - (r1 - r0) * 0.16
            let starC = geo.point(starR, starAngle)
            let starSize = min(11.0, width * 0.16, height * 0.16)
            var star = ctx.resolve(Image(systemName: "star.fill"))
            star.shading = .color(Color(red: 1, green: 0.84, blue: 0.04))
            let ratio = star.size.height > 0 ? starSize / star.size.height : 1
            ctx.draw(star, in: CGRect(x: starC.x - star.size.width * ratio / 2, y: starC.y - starSize / 2, width: star.size.width * ratio, height: starSize))
        }
    }

    /// A group's name along the rim, shrinking to fit and falling back to initials if the arc is too tight.
    private func drawRimLabel(_ ctx: GraphicsContext, _ name: String, arc: Double, mid: Double) {
        let band = labelOuter - outer
        let r = (outer + labelOuter) / 2 + 1
        var size = max(7, min(12, band * 0.5))
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        func length(_ t: String) -> Double { t.map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width + 0.6 }.reduce(0, +) / r }
        var text = name
        while length(text) > arc * 0.94, text.count > 3 { text = String(text.prefix(text.count - 1)) }
        if length(text) > arc * 0.94 { size *= 0.85 }
        drawCurvedText(ctx, text, geo: geo, radius: r, mid: mid, size: size)
    }

    /// A small arrow just inside the rim at each end of the visible arc, showing there's more to reach by dragging.
    private func drawDragHint(_ ctx: GraphicsContext, at angle: Double, pointing: Double) {
        let r = (inner + outer) / 2, c = geo.point(r, angle)
        guard c.x > 0, c.x < geo.size.width, c.y > 0, c.y < geo.size.height else { return }
        let tangent = angle + .pi / 2 * pointing
        let size = 7.0
        var p = Path()
        let tip = CGPoint(x: c.x + size * cos(tangent), y: c.y + size * sin(tangent))
        let backA = CGPoint(x: c.x - size * 0.6 * cos(tangent) + size * 0.6 * cos(angle), y: c.y - size * 0.6 * sin(tangent) + size * 0.6 * sin(angle))
        let backB = CGPoint(x: c.x - size * 0.6 * cos(tangent) - size * 0.6 * cos(angle), y: c.y - size * 0.6 * sin(tangent) - size * 0.6 * sin(angle))
        p.move(to: tip); p.addLine(to: backA); p.addLine(to: backB); p.closeSubpath()
        ctx.fill(p, with: .color(.white.opacity(0.55)))
    }
}
