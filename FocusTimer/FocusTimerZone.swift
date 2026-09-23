import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(FocusTimerZone)
public final class FocusTimerZone: NSObject {
    @objc public var zoneIdentifier: String { "focus-timer" }
    /// Zones (0.13.1 and later) shows this as a button under Settings → Added Zones → Focus Timer.
    @objc public var zoneSettingsTitle: String { "Timer Settings…" }
    @objc public func zoneOpenSettings() { DispatchQueue.main.async { TimerSettingsController.shared.show() } }
    @objc public var zoneTitle: String { "Focus Timer" }
    @objc public var zoneSymbol: String { "timer" }
    @objc public var zonePreferredWidth: NSNumber { 240 }
    @objc public var zonePreferredHeight: NSNumber { 170 }
    /// Zones uses the first entry as this zone's starting position, so the list is ordered: free spots first, "top" last.
    @objc public var zoneAllowedPlacements: [String] { FocusTimerZone.placementOrder() }
    /// Draws across the whole curved shape (a dial). The size slider under Settings → Added Zones uses this range.
    @objc public var zoneUsesFullShape: NSNumber { true }
    @objc public var zoneDefaultScale: NSNumber { 1.0 }
    @objc public var zoneMinimumScale: NSNumber { 0.6 }
    @objc public var zoneMaximumScale: NSNumber { 2.2 }

    public override init() {
        super.init()
        // Bring a running timer back to life as soon as Zones starts, even before the zone is opened.
        DispatchQueue.main.async { TimerModel.shared.startServices() }
    }

    /// A new zone should land on an empty spot. We take a read-only look at where Zones' other zones sit, choose the first
    /// free spot (bottom, right, corners, then the rest) and remember it, so the zone doesn't jump around later.
    static func placementOrder() -> [String] {
        let preference = ["bottom", "right", "topRight", "bottomRight", "topLeft", "left", "bottomLeft", "top"]   // "top" only if nothing else is free
        let d = UserDefaults.standard
        if let saved = d.string(forKey: "ft.defaultPlacement"), preference.contains(saved) {
            return [saved] + preference.filter { $0 != saved }
        }
        var used = Set<String>()
        // (enabled key, placement key, Zones' built-in default position)
        let builtIns: [(String, String, String)] = [
            ("actionEnabled", "placement", "left"), ("todayEnabled", "todayPlacement", "top"), ("audioEnabled", "mediaPlacement", "bottomLeft"),
            ("launchEnabled", "launchPlacement", "bottomRight"), ("communicationsEnabled", "communicationsPlacement", "bottom"),
            ("resourcesEnabled", "resourcesPlacement", "topLeft"), ("controlsEnabled", "controlsPlacement", "right"), ("clipboardEnabled", "clipboardPlacement", "topRight")]
        for (enabledKey, placementKey, fallback) in builtIns where (d.object(forKey: enabledKey) as? Bool ?? (enabledKey == "audioEnabled")) {
            used.insert(d.string(forKey: placementKey) ?? fallback)
        }
        let enabledAdded = d.dictionary(forKey: "installedZoneEnabled") as? [String: Bool] ?? [:]
        let placedAdded = d.dictionary(forKey: "installedZonePlacement") as? [String: String] ?? [:]
        for (id, on) in enabledAdded where on && id != "added.focus-timer" { used.insert(placedAdded[id] ?? "top") }
        let pick = preference.first { !used.contains($0) } ?? "top"
        d.set(pick, forKey: "ft.defaultPlacement")
        return [pick] + preference.filter { $0 != pick }
    }

    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let placement = (context["placement"] as? String) ?? "top"
        ProgressChip.shared.knownPlacement = placement
        let host = NSHostingView(rootView: FocusTimerView(model: TimerModel.shared, placement: placement))
        host.sizingOptions = []
        let box = PassThroughBox(placement: placement)
        host.frame = box.bounds; host.autoresizingMask = [.width, .height]
        box.addSubview(host)
        return box
    }
}

/// Wraps the SwiftUI view so only the slices, buttons and gear take the mouse. A hosting view otherwise claims every click over
/// the whole zone, which stops Zones from seeing a press-and-hold on the empty hub (that is how an open zone is picked up and moved).
final class PassThroughBox: NSView {
    let placement: String
    init(placement: String) { self.placement = placement; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        let geo = TGeo(placement: placement, size: bounds.size)
        let R = geo.radius
        let gear = geo.point(R * 0.13, geo.facing), gr = max(24, R * 0.12) / 2
        let onGear = abs(p.x - gear.x) <= gr && abs(p.y - gear.y) <= gr
        return (onGear || geo.slice(at: p) != nil) ? super.hitTest(point) : nil
    }
    /// A click here should act immediately, even if the panel isn't key yet (it's a non-activating hover panel) — without this, the
    /// first click only brings the panel forward and the button underneath doesn't fire until a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Geometry (the dial's centre is the point on the screen edge or corner the shape grows from)

struct TGeo {
    let placement: String
    let size: CGSize
    var isCorner: Bool { placement.hasPrefix("top") && placement != "top" || placement.hasPrefix("bottom") && placement != "bottom" }
    var radius: Double { (placement == "top" || placement == "bottom") ? size.height : size.width }
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
        default: -3 * .pi / 4
        }
    }
    func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a)) }
    /// Middle angle of each of the four slices, in reading order (left to right, or top to bottom).
    var sliceMids: [Double] {
        let w = span / 4
        let raw = (0..<4).map { facing - span / 2 + w * (Double($0) + 0.5) }
        return raw.sorted { a, b in
            let pa = point(radius * 0.6, a), pb = point(radius * 0.6, b)
            switch placement {
            case "top", "bottom": return pa.x < pb.x
            case "left", "right": return pa.y < pb.y
            default: return abs(pa.y - anchor.y) < abs(pb.y - anchor.y)
            }
        }
    }
    func arc(_ r: Double, _ a0: Double, _ a1: Double) -> Path {
        var p = Path(); let n = 48
        for i in 0...n { let pt = point(r, a0 + (a1 - a0) * Double(i) / Double(n)); if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
        return p
    }
    /// Which slice (0...3) is under a point, worked out from its angle and distance from the anchor.
    func slice(at p: CGPoint) -> Int? {
        let dx = p.x - anchor.x, dy = p.y - anchor.y
        let r = hypot(dx, dy)
        guard r >= radius * 0.30, r <= radius * 0.95 else { return nil }
        let a = atan2(dy, dx)
        let w = span / 4
        for (k, m) in sliceMids.enumerated() {
            var d = a - m
            while d > .pi { d -= 2 * .pi }
            while d <= -.pi { d += 2 * .pi }
            if abs(d) <= w / 2 { return k }
        }
        return nil
    }
}

struct Wedge: Shape {
    let geo: TGeo; let a0: Double; let a1: Double; let r0: Double; let r1: Double
    func path(in rect: CGRect) -> Path {
        var p = Path(); let n = 28
        for i in 0...n { let pt = geo.point(r1, a0 + (a1 - a0) * Double(i) / Double(n)); if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
        for i in 0...n { p.addLine(to: geo.point(r0, a1 + (a0 - a1) * Double(i) / Double(n))) }
        p.closeSubpath(); return p
    }
}

// MARK: - The zone

struct FocusTimerView: View {
    @ObservedObject var model: TimerModel
    let placement: String
    @State private var hover: Int?
    @State private var pressed: Int?

    var body: some View {
        // Nothing here covers the whole zone: only the slices, buttons and gear take the mouse, so holding empty space
        // (the hub) still picks the zone up and moves it, exactly like every other zone.
        GeometryReader { proxy in
            let geo = TGeo(placement: placement, size: proxy.size)
            let R = geo.radius
            ZStack {
                if model.phase == .idle { slices(geo, R) } else { rim(geo, R); readout(geo, R) }
                gear(geo, R)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: idle: four slices
    private func slices(_ geo: TGeo, _ R: Double) -> some View {
        let w = geo.span / 4, mids = geo.sliceMids
        let labelR = R * (geo.isCorner ? 0.68 : 0.64)
        let arc = labelR * w                                          // width available to a label inside its slice
        let numberSize = max(11, min(R * 0.16, arc * 0.46))            // smaller in corners, where slices are narrow
        let unitSize = max(8, numberSize * 0.42)
        return ZStack {
            ForEach(0..<4, id: \.self) { k in
                let mid = mids[k]
                let l = TimerModel.label(model.presets[k])
                let on = hover == k, down = pressed == k
                let shape = Wedge(geo: geo, a0: mid - w / 2 + 0.018, a1: mid + w / 2 - 0.018, r0: R * 0.30, r1: R * 0.93)
                shape.fill(Color.white.opacity(down ? 0.46 : (on ? 0.32 : 0.12)))
                    .overlay(shape.stroke(Color.white.opacity(on || down ? 0.7 : 0.18), lineWidth: on || down ? 1.6 : 1))
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    Text(l.0).font(.system(size: numberSize, weight: .bold, design: .rounded))
                    Text(l.1).font(.system(size: unitSize, weight: .medium)).opacity(0.8)
                }
                .foregroundStyle(.white)
                .scaleEffect(down ? 0.92 : (on ? 1.12 : 1))
                .allowsHitTesting(false)
                .position(geo.point(labelR, mid))
            }
            // One layer handles hover, press and click for all four slices. It works out the slice from the pointer's position, which is
            // reliable where four overlapping shapes were not, and it covers only the slices, so the hub stays free for moving the zone.
            Color.clear
                .contentShape(Wedge(geo: geo, a0: geo.facing - geo.span / 2, a1: geo.facing + geo.span / 2, r0: R * 0.30, r1: R * 0.95))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let k = geo.slice(at: p)
                        if k != hover { hover = k }
                        if k != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    case .ended:
                        hover = nil; pressed = nil; NSCursor.arrow.set()
                    }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let k = geo.slice(at: v.location)
                        pressed = (k != nil && k == geo.slice(at: v.startLocation)) ? k : nil
                    }
                    .onEnded { v in
                        if let k = geo.slice(at: v.startLocation), k == geo.slice(at: v.location) { model.start(slice: k) }
                        pressed = nil
                    })
                .contextMenu {
                    if let k = hover { sliceMenu(k) } else { generalMenu }
                }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    // MARK: running: progress rim + readout
    private func rim(_ geo: TGeo, _ R: Double) -> some View {
        let a0 = geo.facing - geo.span / 2, a1 = geo.facing + geo.span / 2
        let total = max(model.original, model.remaining, 1)
        let p = model.remaining <= 0 ? 0.0 : min(1, model.remaining / total)
        let hot = model.phase == .alarm || model.phase == .overtime
        let tint: Color = hot ? .red : (model.remaining <= 60 ? .orange : .white)
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.pulsing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let glow = model.pulsing ? 0.5 + 0.5 * sin(t * 5) : 0
            ZStack {
                geo.arc(R * 0.955, a0, a1).stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
                if hot { geo.arc(R * 0.955, a0, a1).stroke(Color.red.opacity(0.35 + 0.65 * glow), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round)) }
                else if p > 0 { geo.arc(R * 0.955, a0, a0 + (a1 - a0) * p).stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round)) }
                if model.pulsing { geo.arc(R * 0.955, a0, a1).stroke(tint.opacity(0.35 * glow), style: StrokeStyle(lineWidth: R * 0.11, lineCap: .round)).blur(radius: 5) }
            }
        }.allowsHitTesting(false)
    }

    private func readout(_ geo: TGeo, _ R: Double) -> some View {
        let over = model.remaining < 0
        let caption: String = {
            switch model.phase {
            case .alarm: return "Time's up"
            case .overtime: return "Over by"
            case .paused: return "Paused"
            default:
                let l = TimerModel.label(Int(model.original)); return "of \(l.0) \(l.1)"
            }
        }()
        let corner = geo.isCorner
        return VStack(spacing: R * 0.02) {
            Text(caption.uppercased()).font(.system(size: max(9, R * (corner ? 0.05 : 0.055)), weight: .semibold)).tracking(0.6).opacity(0.7).allowsHitTesting(false)
            Text(TimerModel.clock(model.remaining))
                .font(.system(size: max(18, R * (corner ? 0.16 : 0.2)), weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(over ? Color.red : Color.white).minimumScaleFactor(0.6).lineLimit(1).allowsHitTesting(false)
            if model.added > 0 { Text("+\(Int(model.added / 60)) min added").font(.system(size: max(9, R * 0.05))).opacity(0.65).allowsHitTesting(false) }
            HStack(spacing: R * 0.035) {
                if model.phase == .running || model.phase == .paused {
                    circle(model.phase == .paused ? "play.fill" : "pause.fill", model.phase == .paused ? "Resume" : "Pause", R) { model.togglePause() }
                }
                circle("plus", "Add \(model.snoozeMinutes) minutes", R, label: "\(model.snoozeMinutes)") { model.snooze() }
                if model.phase == .alarm { circle("bell.slash.fill", "Stop the alarm", R) { model.stopAlarm() } }
                circle("arrow.counterclockwise", "Reset", R) { model.reset() }
            }.padding(.top, R * 0.02)
        }
        .foregroundStyle(.white)
        .frame(width: R * 0.78)
        .position(geo.point(R * (corner ? 0.56 : 0.5), geo.facing))
    }

    private func circle(_ symbol: String, _ tip: String, _ R: Double, label: String? = nil, action: @escaping () -> Void) -> some View {
        let s = max(24, R * 0.13)
        return Button(action: action) {
            HStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: s * 0.42, weight: .semibold))
                if let label { Text(label).font(.system(size: s * 0.36, weight: .bold)) }
            }
            .foregroundStyle(.white).frame(minWidth: s, minHeight: s)
            .background(Capsule().fill(Color.white.opacity(0.16)))
        }.buttonStyle(.plain).help(tip)
        .contextMenu { generalMenu }
    }

    private func gear(_ geo: TGeo, _ R: Double) -> some View {
        Button { TimerSettingsController.shared.show() } label: {
            Image(systemName: "gearshape.fill").font(.system(size: max(11, R * 0.075))).foregroundStyle(.white.opacity(0.85))
                .frame(width: max(24, R * 0.12), height: max(24, R * 0.12)).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Timer settings")
        .contextMenu { generalMenu }
        .position(geo.point(R * 0.13, geo.facing))
    }

    // MARK: right-click menus
    @ViewBuilder private var generalMenu: some View {
        if model.phase == .running || model.phase == .paused { Button(model.phase == .paused ? "Resume" : "Pause") { model.togglePause() } }
        if model.phase != .idle {
            Button("Add \(model.snoozeMinutes) minutes") { model.snooze() }
            if model.phase == .alarm { Button("Stop the alarm") { model.stopAlarm() } }
            Button("Reset timer") { model.reset() }
            Divider()
        }
        Button("Timer settings…") { TimerSettingsController.shared.show() }
        Button("Zone size…") { TimerSettingsController.openZonesSettings() }
    }
    @ViewBuilder private func sliceMenu(_ k: Int) -> some View {
        Text("Timer \(k + 1): \(TimerModel.label(model.presets[k]).0) \(TimerModel.label(model.presets[k]).1)")
        Divider()
        ForEach([1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { m in
            Button("\(m) min") { model.setPreset(k, minutes: m) }
        }
        Divider()
        Button("Timer settings…") { TimerSettingsController.shared.show() }
        Button("Zone size…") { TimerSettingsController.openZonesSettings() }
    }
}
