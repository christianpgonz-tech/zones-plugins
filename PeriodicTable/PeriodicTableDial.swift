import AppKit
import SwiftUI

/// Where the dial sits inside the docked shape. The dial's center is the point on the screen edge
/// (or corner) the shape grows from, so only the half or quarter that's on screen is visible.
struct DialGeometry {
    static let step = 2 * Double.pi / 20          // 18 groups + 2 spare slots around the full circle
    let placement: String
    let size: CGSize

    static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x <= -.pi { x += 2 * .pi }
        return x
    }
    /// The screen direction (y down) the visible part of the dial faces.
    static func centerAngle(placement: String) -> Double {
        switch placement {
        case "top": .pi / 2
        case "bottom": -.pi / 2
        case "left": 0
        case "right": .pi
        case "topLeft": .pi / 4
        case "topRight": 3 * .pi / 4
        case "bottomLeft": -.pi / 4
        default: -3 * .pi / 4
        }
    }
    /// Starts with the transition metals in view.
    static func startRotation(placement: String) -> Double { centerAngle(placement: placement) - 7.5 * step }

    var isCorner: Bool { placement.hasPrefix("top") && placement != "top" || placement.hasPrefix("bottom") && placement != "bottom" }
    var radius: Double {
        switch placement {
        case "top", "bottom": size.height
        case "left", "right": size.width
        default: size.width
        }
    }
    var anchor: CGPoint {
        switch placement {
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
    var span: Double { isCorner ? .pi / 2 : .pi }
    var facing: Double { Self.centerAngle(placement: placement) }
    func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a)) }

    // Ring layout: nine rings (periods 1–7, then lanthanides, then actinides) between the hub and the rim.
    var innerRadius: Double { radius * (isCorner ? 0.22 : 0.15) }
    var ringThickness: Double { (radius * 0.97 - innerRadius) / 9 }
    static func ring(forRow y: Int) -> Int { y <= 7 ? y - 1 : y - 2 }

    /// The largest rectangle of the given proportions that fits inside the curved shape, and where it goes.
    /// Slides it along the shape's centre line and grows it until the corners touch the rim or the screen edge.
    func bestFit(design: CGSize, margin: CGFloat = 10) -> (scale: CGFloat, center: CGPoint) {
        var k: CGFloat = 3
        while k > 0.3 {
            let hw = design.width * k / 2, hh = design.height * k / 2
            for step in stride(from: 0.15, through: 1.0, by: 0.02) {
                let c = point(radius * step, facing)
                let ok = [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)].allSatisfy { corner in
                    let p = CGPoint(x: c.x + corner.0 * hw, y: c.y + corner.1 * hh)
                    return hypot(p.x - anchor.x, p.y - anchor.y) <= radius * 0.93 && p.x >= margin && p.y >= margin && p.x <= size.width - margin && p.y <= size.height - margin
                }
                if ok { return (k, c) }
            }
            k -= 0.02
        }
        return (0.3, point(radius * 0.5, facing))
    }
}

private let grid: [Int: Element] = {
    var g: [Int: Element] = [:]
    for e in allElements { g[e.x * 100 + DialGeometry.ring(forRow: e.y)] = e }
    return g
}()

extension Family {
    /// Bright, solid colours with dark text, so the dial stays readable over the frosted background.
    var dialColor: Color {
        switch self {
        case .alkali: Color(hue: 0.99, saturation: 0.60, brightness: 0.98)
        case .alkalineEarth: Color(hue: 0.07, saturation: 0.62, brightness: 0.98)
        case .transition: Color(hue: 0.58, saturation: 0.48, brightness: 0.98)
        case .postTransition: Color(hue: 0.45, saturation: 0.46, brightness: 0.92)
        case .metalloid: Color(hue: 0.33, saturation: 0.48, brightness: 0.90)
        case .nonmetal: Color(hue: 0.14, saturation: 0.62, brightness: 0.99)
        case .noble: Color(hue: 0.76, saturation: 0.40, brightness: 0.98)
        case .lanthanide: Color(hue: 0.90, saturation: 0.42, brightness: 0.98)
        case .actinide: Color(hue: 0.82, saturation: 0.50, brightness: 0.92)
        }
    }
}

struct DialView: View {
    @ObservedObject var model: TableModel
    let geo: DialGeometry
    @State private var lastAngle: Double?
    @State private var lastTime: Date?
    @State private var travel: CGFloat = 0
    @State private var startPoint: CGPoint = .zero

    var body: some View {
        let matches = Set(model.results.map(\.number))
        let searching = !model.query.isEmpty
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(ctx, matches: matches, searching: searching) }
            hub
            if let hovered = model.hoveredDial, !model.dragging, let pointer = model.pointer { card(for: hovered).position(cardPosition(for: hovered, pointer: pointer)).allowsHitTesting(false) }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                model.pointer = p
                model.hoveredDial = element(at: p)
                if model.dragging { NSCursor.closedHand.set() }
                else if onDial(p) { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            case .ended:
                model.pointer = nil; model.hoveredDial = nil
                if !model.dragging { NSCursor.arrow.set() }
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let angle = atan2(value.location.y - geo.anchor.y, value.location.x - geo.anchor.x)
                if lastAngle == nil { lastAngle = angle; lastTime = Date(); travel = 0; startPoint = value.location; model.goal = nil; model.omega = 0 }
                travel = max(travel, hypot(value.location.x - startPoint.x, value.location.y - startPoint.y))
                guard travel > 4, let previous = lastAngle else { return }
                model.dragging = true; model.hasRotated = true
                NSCursor.closedHand.set()
                let delta = DialGeometry.wrap(angle - previous)
                let now = Date(), dt = max(0.001, now.timeIntervalSince(lastTime ?? now))
                model.rotation += delta
                model.omega = model.omega * 0.6 + (delta / dt) * 0.4
                lastAngle = angle; lastTime = now
            }
            .onEnded { value in
                let wasDrag = model.dragging
                lastAngle = nil; model.dragging = false
                if wasDrag {
                    model.omega = max(-9, min(9, model.omega)); model.startTicker()
                    if onDial(value.location) { NSCursor.openHand.set() }
                } else if let element = element(at: value.location) { model.open(element) }
            })
    }

    // MARK: Hit testing

    private func onDial(_ p: CGPoint) -> Bool {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        return r >= geo.innerRadius - 4 && r <= geo.radius
    }
    private func element(at p: CGPoint) -> Element? {
        let r = hypot(p.x - geo.anchor.x, p.y - geo.anchor.y)
        let ring = Int(floor((r - geo.innerRadius) / geo.ringThickness))
        guard ring >= 0, ring < 9 else { return nil }
        var local = atan2(p.y - geo.anchor.y, p.x - geo.anchor.x) - model.rotation
        local = local.truncatingRemainder(dividingBy: 2 * .pi)
        if local < 0 { local += 2 * .pi }
        let col = Int(local / DialGeometry.step) + 1
        guard col <= 18 else { return nil }
        return grid[col * 100 + ring]
    }

    // MARK: Drawing

    private func tilePath(ring: Int, a0: Double, a1: Double, grow: Double = 1) -> Path {
        let r0 = geo.innerRadius + Double(ring) * geo.ringThickness + 0.8
        let r1 = r0 + geo.ringThickness - 1.6
        let mid = (a0 + a1) / 2, rm = (r0 + r1) / 2
        let inset0 = 0.9 / r0, inset1 = 0.9 / r1
        var pts: [CGPoint] = []
        let n = 6
        for i in 0...n { pts.append(geo.point(r1, a0 + inset1 + (a1 - a0 - 2 * inset1) * Double(i) / Double(n))) }
        for i in stride(from: n, through: 0, by: -1) { pts.append(geo.point(r0, a0 + inset0 + (a1 - a0 - 2 * inset0) * Double(i) / Double(n))) }
        if grow != 1 {
            let c = geo.point(rm, mid)
            pts = pts.map { CGPoint(x: c.x + ($0.x - c.x) * grow, y: c.y + ($0.y - c.y) * grow) }
        }
        var path = Path(); path.move(to: pts[0]); pts.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath()
        return path
    }

    private func draw(_ ctx: GraphicsContext, matches: Set<Int>, searching: Bool) {
        var hoveredDraw: (element: Element, ring: Int, a0: Double, a1: Double, center: CGPoint, symbolSize: Double, ink: Color)?
        for e in allElements {
            let a0 = model.rotation + Double(e.x - 1) * DialGeometry.step
            let a1 = a0 + DialGeometry.step
            let d = DialGeometry.wrap((a0 + a1) / 2 - geo.facing)
            guard abs(d) <= geo.span / 2 + DialGeometry.step else { continue }
            let ring = DialGeometry.ring(forRow: e.y)
            let hovered = model.hoveredDial == e && !model.dragging
            let dimmed = searching && !matches.contains(e.number)
            var layer = ctx
            layer.opacity = dimmed ? 0.16 : 1
            layer.fill(tilePath(ring: ring, a0: a0, a1: a1), with: .color(e.family.dialColor))
            let rm = geo.innerRadius + (Double(ring) + 0.5) * geo.ringThickness
            let arcWidth = rm * DialGeometry.step
            let center = geo.point(rm, (a0 + a1) / 2)
            let ink = Color.black.opacity(0.85)
            let symbolSize = min(geo.ringThickness * 0.46, arcWidth * 0.36, 16)
            let nameSize = max(6, min(7.5, geo.ringThickness * 0.25))
            let nameFits = arcWidth * 0.9 >= Double(e.name.count) * nameSize * 0.53 && geo.ringThickness >= 22
            if arcWidth >= 24 && geo.ringThickness >= 20 {
                layer.draw(Text(e.symbol).font(.system(size: symbolSize, weight: .bold)).foregroundColor(ink), at: CGPoint(x: center.x, y: center.y - symbolSize * 0.28))
                let second = nameFits ? e.name : "\(e.number)"
                layer.draw(Text(second).font(.system(size: nameSize)).foregroundColor(ink.opacity(0.8)), at: CGPoint(x: center.x, y: center.y + symbolSize * 0.72))
            } else if arcWidth >= 16 {
                layer.draw(Text(e.symbol).font(.system(size: symbolSize, weight: .bold)).foregroundColor(ink), at: center)
            }
            if searching && matches.contains(e.number) {
                layer.stroke(tilePath(ring: ring, a0: a0, a1: a1), with: .color(.white), lineWidth: 2)
            }
            if hovered { hoveredDraw = (e, ring, a0, a1, center, symbolSize, ink) }
        }
        // Drawn after every other tile so no neighbour can cover its outline; the shadow lifts it off the dial.
        if let h = hoveredDraw {
            let big = tilePath(ring: h.ring, a0: h.a0, a1: h.a1, grow: 1.35)
            var lifted = ctx
            lifted.addFilter(.shadow(color: .black.opacity(0.55), radius: 9, x: 0, y: 4))
            lifted.fill(big, with: .color(h.element.family.dialColor))
            ctx.stroke(big, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            ctx.draw(Text(h.element.symbol).font(.system(size: min(22, h.symbolSize * 1.5), weight: .bold)).foregroundColor(h.ink), at: h.center)
        }
    }

    // MARK: Hub and hover card

    private var hub: some View {
        // Corners: keep the whole block well clear of the screen edge; edges: just off the middle of the flat side.
        let p = geo.isCorner ? geo.point(geo.innerRadius * 0.68, geo.facing) : geo.point(geo.radius * 0.095, geo.facing)
        return VStack(spacing: 4) {
            if !model.hasRotated {
                Image(systemName: "hand.draw").font(.system(size: 15))
                Text("Drag to rotate").font(.system(size: 10, weight: .medium))
            }
            if !model.query.isEmpty { Text(model.query).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
            else if model.hasRotated { Text("Type to search").font(.system(size: 10)).foregroundStyle(.secondary) }
            Button { TableWindowController.shared.show() } label: {
                Label("Table", systemImage: "square.grid.3x3").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.primary.opacity(0.16)))
            }.buttonStyle(.plain).help("Open the full table in its own window")
        }.foregroundStyle(.primary).fixedSize().position(p)
    }

    private var cardScale: CGFloat { max(1, geo.radius / 300) }
    private func cardPosition(for e: Element, pointer: CGPoint) -> CGPoint {
        let ring = DialGeometry.ring(forRow: e.y)
        let rm = geo.innerRadius + (Double(ring) + 0.5) * geo.ringThickness
        let tile = geo.point(rm, model.rotation + (Double(e.x) - 0.5) * DialGeometry.step)
        // Push the card away from its tile toward the middle of the shape, then keep it fully on screen.
        let toward = geo.point(geo.radius * 0.5, geo.facing)
        let dx = toward.x - tile.x, dy = toward.y - tile.y, len = max(1, hypot(dx, dy))
        let s = cardScale, hw = 130 * s, hh = 68 * s
        var c = CGPoint(x: tile.x + dx / len * (hw + 20), y: tile.y + dy / len * (hh + 24))
        c.x = min(max(c.x, hw + 6), geo.size.width - hw - 6); c.y = min(max(c.y, hh + 6), geo.size.height - hh - 6)
        return c
    }

    private func card(for e: Element) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(e.number)").font(.system(size: 12).monospacedDigit())
                Text(e.symbol).font(.system(size: 34, weight: .bold))
                Text(e.mass.map { String(format: "%.2f", $0) } ?? "").font(.system(size: 10).monospacedDigit())
            }.frame(width: 66, height: 74).foregroundStyle(.black.opacity(0.85)).background(RoundedRectangle(cornerRadius: 8).fill(e.family.dialColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                Text(e.category.lowercased().hasPrefix("unknown") ? "Probably \(e.family.title.lowercased())" : e.family.title).font(.system(size: 12, weight: .medium)).foregroundStyle(e.family.dialColor)
                if e.measured {
                    Text(e.phase.map { "\($0) at room temperature" } ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Melts \(model.unit.format(kelvin: e.melt))  ·  Boils \(model.unit.format(kelvin: e.boil))").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    if let d = e.density { Text("Density \(String(format: "%g", d)) g/cm³").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary) }
                } else { Text("Predicted properties").font(.system(size: 12)).foregroundStyle(.secondary) }
                Text("Click for the full card").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(12).frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.18)))
        .shadow(radius: 8)
        .scaleEffect(cardScale * 0.87)
    }
}
