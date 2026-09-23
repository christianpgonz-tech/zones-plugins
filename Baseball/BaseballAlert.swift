import AppKit
import SwiftUI

/// What the score pop-up shows.
struct ScoreAlertInfo: Identifiable {
    let id = UUID()
    let kind: String            // "HOME RUN", "GRAND SLAM", "RUN SCORES"
    let team: String            // who scored
    let points: Int
    let game: Game
}

/// A larger card that opens beside the zone's icon when a team scores, then closes itself.
/// It is its own floating window, so it never has to resize the zone.
final class BaseballScoreAlert {
    static let shared = BaseballScoreAlert()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ info: ScoreAlertInfo) {
        let store = BaseballStore.shared
        let seconds = store.alertSeconds
        hideWork?.cancel()
        let size = CGSize(width: 400, height: 210)
        let view = ScoreAlertView(info: info, seconds: seconds, start: Date(), close: { [weak self] in self?.hide() },
                                  open: { [weak self] in self?.hide(); BaseballDetailsController.shared.show(team: info.team, game: info.game) })
        if panel == nil {
            let p = BaseballAlertPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: view)
        panel?.setFrame(target(size), display: true)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel?.animator().alphaValue = 1 }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    /// Next to the zone's small icon, on the side facing the middle of the screen; top centre if the icon can't be found.
    private func target(_ size: CGSize) -> NSRect {
        let handle = NSApp.windows.first { $0.title == "MLB Baseball" && $0.isVisible && $0.frame.width <= 96 && $0.frame.height <= 96 }
        let screen = handle?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        var center = CGPoint(x: vis.midX, y: vis.maxY - size.height / 2 - 24)
        if let h = handle {
            let hc = CGPoint(x: h.frame.midX, y: h.frame.midY), sc = CGPoint(x: vis.midX, y: vis.midY)
            let dx = sc.x - hc.x, dy = sc.y - hc.y, len = max(1, hypot(dx, dy))
            center = CGPoint(x: hc.x + dx / len * (size.width / 2 + 60), y: hc.y + dy / len * (size.height / 2 + 60))
        }
        let x = min(max(center.x - size.width / 2, vis.minX + 12), vis.maxX - size.width - 12)
        let y = min(max(center.y - size.height / 2, vis.minY + 12), vis.maxY - size.height - 12)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

final class BaseballAlertPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct ScoreAlertView: View {
    let info: ScoreAlertInfo
    let seconds: Double
    let start: Date
    let close: () -> Void
    let open: () -> Void
    @ObservedObject var store = BaseballStore.shared
    @State private var appeared = false

    var body: some View {
        let team = store.team(info.team)
        let g = info.game
        let color = team?.color ?? .orange
        VStack(spacing: 0) {
            HStack {
                Text(info.kind).font(.system(size: 20, weight: .heavy)).tracking(1.5)
                Text(team?.school.uppercased() ?? info.team).font(.system(size: 14, weight: .bold)).opacity(0.9)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).opacity(0.8) }.buttonStyle(.plain).help("Dismiss")
            }.padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(.white).background(color)
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    side(g.away, g.awayScore)
                    Text("–").font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
                    side(g.home, g.homeScore)
                }
                Text(playText(g)).font(.system(size: 13)).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                Text(g.statusLine).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxHeight: .infinity)
            TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                let f = max(0, 1 - ctx.date.timeIntervalSince(start) / seconds)
                GeometryReader { p in Rectangle().fill(color).frame(width: p.size.width * f) }.frame(height: 3)
            }
        }
        .frame(width: 400, height: 210)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.18)))
        .contentShape(Rectangle()).onTapGesture(perform: open)
        .scaleEffect(appeared ? 1 : 0.85).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { appeared = true } }
        .environment(\.colorScheme, .dark)
    }

    private func side(_ abbr: String, _ score: Int) -> some View {
        let scored = abbr == info.team
        return VStack(spacing: 3) {
            TeamLogo(abbr: abbr, size: 46).shadow(color: scored ? (store.team(abbr)?.color ?? .white) : .clear, radius: 9)
            Text("\(score)").font(.system(size: 34, weight: .heavy).monospacedDigit()).foregroundStyle(scored ? Color.primary : .secondary)
        }.frame(width: 96)
    }
    /// The play text from the live feed, otherwise a plain summary.
    private func playText(_ g: Game) -> String {
        if let p = g.lastPlay, !p.isEmpty { return p }
        return "\(store.team(info.team)?.name ?? info.team) score. It's \(g.away) \(g.awayScore), \(g.home) \(g.homeScore)."
    }
}
