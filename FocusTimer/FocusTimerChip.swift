import AppKit
import SwiftUI

/// A thin progress ring drawn just outside the zone's small handle while a timer runs, the way the volume
/// dial shows level, so you can see the time left without opening the zone. It pulses when time is up.
/// It ignores the mouse completely, so the handle underneath still works normally.
final class ProgressChip {
    static let shared = ProgressChip()
    var knownPlacement: String?
    private var panel: NSPanel?
    private var timer: Timer?
    private let state = ChipState()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// The small handle window Zones draws for this zone (its title is the zone's name).
    private func handle() -> NSWindow? { NSApp.windows.first { $0.title == "Focus Timer" && $0.isVisible } }

    private func tick() {
        let m = TimerModel.shared
        guard m.phase != .idle, let h = handle(), h.frame.width <= 96, h.frame.height <= 96 else { panel?.orderOut(nil); return }
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
        let side = 2 * (R + 18)
        if panel == nil {
            let p = ChipPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: ChipView(state: state))
            panel = p
        }
        panel?.level = NSWindow.Level(rawValue: h.level.rawValue + 1)
        panel?.setFrame(NSRect(x: anchor.x - side / 2, y: anchor.y - side / 2, width: side, height: side), display: false)
        let total = max(m.original, m.remaining, 1)
        state.update(placement: placement, radius: R, fraction: m.remaining <= 0 ? 0 : min(1, m.remaining / total),
                     hot: m.phase == .alarm || m.phase == .overtime, low: m.remaining <= 60, pulsing: m.pulsing)
        panel?.orderFrontRegardless()
    }
}

final class ChipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Lets the ring hang off the screen edge (only the part on screen is visible).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class ChipState: ObservableObject {
    @Published var placement = "top"
    @Published var radius: CGFloat = 32
    @Published var fraction = 1.0
    @Published var hot = false
    @Published var low = false
    @Published var pulsing = false
    func update(placement: String, radius: CGFloat, fraction: Double, hot: Bool, low: Bool, pulsing: Bool) {
        if self.placement != placement { self.placement = placement }
        if self.radius != radius { self.radius = radius }
        if abs(self.fraction - fraction) > 0.002 { self.fraction = fraction }
        if self.hot != hot { self.hot = hot }
        if self.low != low { self.low = low }
        if self.pulsing != pulsing { self.pulsing = pulsing }
    }
}

struct ChipView: View {
    @ObservedObject var state: ChipState
    var body: some View {
        GeometryReader { proxy in
            let c = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let geo = TGeo(placement: state.placement, size: proxy.size)
            let a0 = geo.facing - geo.span / 2, a1 = geo.facing + geo.span / 2
            let r = Double(state.radius) + 6
            let tint: Color = state.hot ? .red : (state.low ? .orange : .white)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.pulsing)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let ph = state.pulsing ? (t * 1.6).truncatingRemainder(dividingBy: 1) : 0
                ZStack {
                    arc(c, r, a0, a1).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    if state.hot { arc(c, r, a0, a1).stroke(Color.red.opacity(state.pulsing ? 0.55 + 0.45 * sin(t * 6) : 0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round)) }
                    else if state.fraction > 0 { arc(c, r, a0, a0 + (a1 - a0) * state.fraction).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)) }
                    if state.pulsing {
                        arc(c, r + 12 * ph, a0, a1).stroke(tint.opacity(0.75 * (1 - ph)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
            }
        }
    }
    private func arc(_ c: CGPoint, _ r: Double, _ a0: Double, _ a1: Double) -> Path {
        var p = Path(); let n = 40
        for i in 0...n {
            let a = a0 + (a1 - a0) * Double(i) / Double(n)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
