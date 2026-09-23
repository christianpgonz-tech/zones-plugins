import AppKit
import SwiftUI

/// A thin four-segment dial drawn just outside the zone's small handle while one of your teams is playing (or about to),
/// so you can see how far into the game it is without opening anything. One segment per quarter, filling as time runs.
/// It ignores the mouse completely, so the handle underneath still works normally.
final class FBChip {
    static let shared = FBChip()
    private var panel: NSPanel?
    private var timer: Timer?
    private let state = FBChipState()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    /// The small handle window Zones draws for this zone (its title is the zone's name).
    private func handle() -> NSWindow? { NSApp.windows.first { $0.title == "NFL Football" && $0.isVisible } }

    private func tick() {
        let store = FootballStore.shared
        guard store.chipEnabled, let tracked = store.trackedGame, let h = handle(), h.frame.width <= 96, h.frame.height <= 96 else { panel?.orderOut(nil); return }
        let f = h.frame, s = (h.screen ?? NSScreen.main)?.frame ?? f
        let nearL = f.minX - s.minX < 6, nearR = s.maxX - f.maxX < 6, nearB = f.minY - s.minY < 6, nearT = s.maxY - f.maxY < 70
        let placement: String
        if (nearL || nearR) && (nearT || nearB) { placement = (nearT ? "top" : "bottom") + (nearL ? "Left" : "Right") }
        else if nearT { placement = "top" } else if nearB { placement = "bottom" } else if nearL { placement = "left" } else { placement = "right" }
        let corner = placement.count > 6
        let R: CGFloat = corner ? f.width : (placement == "top" || placement == "bottom" ? f.width / 2 : f.height / 2)
        let anchor: CGPoint
        switch placement {
        case "top": anchor = CGPoint(x: f.midX, y: f.maxY)
        case "bottom": anchor = CGPoint(x: f.midX, y: f.minY)
        case "left": anchor = CGPoint(x: f.minX, y: f.midY)
        case "right": anchor = CGPoint(x: f.maxX, y: f.midY)
        case "topLeft": anchor = CGPoint(x: f.minX, y: f.maxY)
        case "topRight": anchor = CGPoint(x: f.maxX, y: f.maxY)
        case "bottomLeft": anchor = CGPoint(x: f.minX, y: f.minY)
        default: anchor = CGPoint(x: f.maxX, y: f.minY)
        }
        let side = 2 * (R + 34)
        if panel == nil {
            let p = FBChipPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: FBChipView(state: state))
            panel = p
        }
        panel?.level = NSWindow.Level(rawValue: h.level.rawValue + 1)
        panel?.setFrame(NSRect(x: anchor.x - side / 2, y: anchor.y - side / 2, width: side, height: side), display: false)
        let g = tracked.game, me = tracked.team.abbr
        let mine = g.score(of: me), theirs = g.score(of: g.opponent(of: me))
        let q = g.period > 4 ? "OT" : "Q\(max(1, g.period))"
        let label: String
        switch g.state {
        case .live: label = g.statusLine == "Halftime" ? "HT \(mine)–\(theirs)" : "\(q) \(mine)–\(theirs)"
        default: let m = max(0, Int(g.date.timeIntervalSinceNow / 60)); label = m > 0 ? "in \(m)m" : "Kickoff"
        }
        state.update(placement: placement, radius: R, progress: g.progress, live: g.state == .live,
                     lead: mine > theirs ? 1 : (mine < theirs ? -1 : 0), redZone: g.state == .live && g.redZone && g.possession == me,
                     hasBall: g.state == .live && g.possession == me, label: label)
        panel?.orderFrontRegardless()
    }
}

final class FBChipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Lets the ring hang off the screen edge (only the part on screen is visible).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class FBChipState: ObservableObject {
    @Published var placement = "top"
    @Published var radius: CGFloat = 32
    @Published var progress = 0.0
    @Published var live = false
    @Published var lead = 0            // 1 = your team is ahead, -1 = behind, 0 = tied
    @Published var redZone = false
    @Published var hasBall = false
    @Published var label = ""
    func update(placement: String, radius: CGFloat, progress: Double, live: Bool, lead: Int, redZone: Bool, hasBall: Bool, label: String) {
        if self.placement != placement { self.placement = placement }
        if self.radius != radius { self.radius = radius }
        if abs(self.progress - progress) > 0.001 { self.progress = progress }
        if self.live != live { self.live = live }
        if self.lead != lead { self.lead = lead }
        if self.redZone != redZone { self.redZone = redZone }
        if self.hasBall != hasBall { self.hasBall = hasBall }
        if self.label != label { self.label = label }
    }
}

/// What the little dial says:
///  - The white ring is the clock: four quarters, filling as the game goes on (the current quarter is the brightest).
///  - The dot at the end of the fill is the score: green = your team is ahead, red = behind, grey = tied.
///  - The whole ring pulses when your team has the ball inside the 20-yard line (the red zone).
///  - The small label gives the quarter and score (a football icon appears when your team has the ball).
struct FBChipView: View {
    @ObservedObject var state: FBChipState
    var body: some View {
        GeometryReader { proxy in
            let geo = FGeo(placement: state.placement, size: proxy.size)
            let c = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let start = geo.facing - geo.span / 2
            let r = Double(state.radius) + 6
            let gap = 0.045, w = geo.span / 4
            let dotColor: Color = state.lead > 0 ? Color(red: 0.19, green: 0.82, blue: 0.35) : state.lead < 0 ? Color(red: 1, green: 0.27, blue: 0.23) : Color.white.opacity(0.75)
            let currentQuarter = min(3, Int(state.progress * 4))
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !state.redZone)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let pulse = state.redZone ? 0.5 + 0.5 * sin(t * 5) : 0
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        let a0 = start + w * Double(i) + gap / 2, a1 = start + w * Double(i + 1) - gap / 2
                        let fill = max(0, min(1, state.progress * 4 - Double(i)))
                        arc(c, r, a0, a1).stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        if fill > 0 {
                            arc(c, r, a0, a0 + (a1 - a0) * fill)
                                .stroke(Color.white.opacity(state.live && i == currentQuarter ? 1 : 0.6), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        }
                    }
                    if state.redZone { arc(c, r, start, start + geo.span).stroke(Color.red.opacity(0.35 + 0.5 * pulse), style: StrokeStyle(lineWidth: 6, lineCap: .round)).blur(radius: 1.5) }
                    if state.live {
                        let q = min(3, Int(state.progress * 4))
                        let a = start + w * Double(q) + gap / 2 + (w - gap) * max(0, min(1, state.progress * 4 - Double(q)))
                        let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                        Circle().fill(dotColor).frame(width: 9, height: 9).shadow(color: dotColor.opacity(0.9), radius: 4).position(p)
                    }
                    HStack(spacing: 3) {
                        if state.hasBall { Image(systemName: "football.fill").font(.system(size: 8)) }
                        Text(state.label).font(.system(size: 9, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .position(labelPosition(c: c, r: r, facing: geo.facing, size: proxy.size))
                }
            }
        }
    }
    /// The label sits just outside the ring on the side facing the screen, kept fully inside this window.
    private func labelPosition(c: CGPoint, r: Double, facing: Double, size: CGSize) -> CGPoint {
        let halfW = (Double(state.label.count) * 6.2 + (state.hasBall ? 12 : 0) + 14) / 2, halfH = 9.0
        let x = c.x + (r + 17) * cos(facing), y = c.y + (r + 17) * sin(facing)
        return CGPoint(x: min(max(x, halfW + 2), size.width - halfW - 2), y: min(max(y, halfH + 2), size.height - halfH - 2))
    }
    private func arc(_ c: CGPoint, _ r: Double, _ a0: Double, _ a1: Double) -> Path {
        var p = Path(); let n = 24
        for i in 0...n {
            let a = a0 + (a1 - a0) * Double(i) / Double(n)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
