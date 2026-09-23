import AppKit
import SwiftUI

enum SoccerMode { case cards, matches, picker }

final class SoccerUI: ObservableObject {
    init(mode: SoccerMode = .cards) { self.mode = mode }
    @Published var mode: SoccerMode
    @Published var cardIndex = 0
    @Published var daysAhead = 14
    @Published var pastDays = 0
    @Published var leagueFilter: String?        // nil = all three leagues
    @Published var hoveringCard = false
    /// A goal (or red card) being celebrated on the card (the zone opened for it).
    @Published var celebration: ScoreAlertInfo?
    let picker = PickerState()                    // the club picker's search and filter
}

/// Tells the wrapper view which points belong to the zone's content, so a press on empty space still reaches Zones
/// (that is how an open zone is picked up and moved).
final class SCHitMap { var contains: (CGPoint) -> Bool = { _ in true } }

final class SCPassThroughBox: NSView {
    let hit: SCHitMap
    init(hit: SCHitMap) { self.hit = hit; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p), hit.contains(p) else { return nil }
        return super.hitTest(point)
    }
    /// A click here should act immediately, even if the panel isn't key yet (it's a non-activating hover panel) — without this, the
    /// first click only brings the panel forward and the button underneath doesn't fire until a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Root view

struct SoccerView: View {
    let placement: String
    let hit: SCHitMap
    @ObservedObject var store = SoccerStore.shared
    init(placement: String, hit: SCHitMap, startMode: SoccerMode = .cards) {
        self.placement = placement; self.hit = hit
        _ui = StateObject(wrappedValue: SoccerUI(mode: startMode))
    }
    @StateObject private var ui: SoccerUI
    private let design = CGSize(width: 320, height: 272)
    /// Which league mark fills the empty space below the card: the shown match's league, or the Matches filter (all three if none).
    private var badgeLeagues: [String] {
        switch ui.mode {
        case .picker: return []
        case .matches: return ui.leagueFilter.map { [$0] } ?? League.all.map(\.code)
        case .cards:
            guard !store.favorites.isEmpty else { return League.all.map(\.code) }
            let key = ui.celebration?.team ?? store.favorites[ui.cardIndex % store.favorites.count]
            return [store.currentMatch(for: key)?.league ?? store.team(key)?.league ?? "eng.1"]
        }
    }
    private let rotator = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var sinceRotate = 0.0

    var body: some View {
        GeometryReader { proxy in
            let geo = FGeo(placement: placement, size: proxy.size)
            ZStack(alignment: .topLeading) {
                if ui.mode == .picker {
                    let _ = hit.contains = { p in hypot(p.x - geo.anchor.x, p.y - geo.anchor.y) <= geo.radius }
                    SportsDial(store: store, state: ui.picker, geo: geo, onDone: { ui.mode = .cards; ui.picker.reset() })
                } else {
                    let fit = geo.bestFit(design: design)
                    let rect = CGRect(x: fit.center.x - design.width * fit.scale / 2, y: fit.center.y - design.height * fit.scale / 2, width: design.width * fit.scale, height: design.height * fit.scale)
                    let _ = hit.contains = { rect.insetBy(dx: -6, dy: -6).contains($0) }
                    let codes = badgeLeagues
                    if !codes.isEmpty, let spot = LeagueBadge.spot(geo: geo, rect: rect, codes: codes) {
                        LeagueBadge(codes: codes, size: spot.size).position(spot.center).allowsHitTesting(false)
                    }
                    PanelCanvas(ui: ui, store: store)
                        .frame(width: design.width, height: design.height)
                        .scaleEffect(fit.scale)
                        .frame(width: rect.width, height: rect.height)
                        .position(fit.center)
                }
            }
        }
        .clipped()
        .onReceive(store.$scoreEvent.compactMap { $0 }) { info in
            // A goal (or red card): show that match's card with a celebration banner for as long as the alert setting says.
            ui.mode = .cards; ui.celebration = info; sinceRotate = 0
            if let i = store.favorites.firstIndex(of: info.team) { ui.cardIndex = i }
            DispatchQueue.main.asyncAfter(deadline: .now() + store.alertSeconds) { if ui.celebration?.id == info.id { withAnimation { ui.celebration = nil } } }
        }
        .onReceive(rotator) { _ in
            // Favorite cards take turns; hovering a card holds it still.
            guard ui.mode == .cards, ui.celebration == nil, !ui.hoveringCard, store.favorites.count > 1, store.rotateSeconds > 0 else { sinceRotate = 0; return }
            sinceRotate += 1
            if sinceRotate >= store.rotateSeconds { sinceRotate = 0; ui.cardIndex = (ui.cardIndex + 1) % store.favorites.count }
        }
    }
}

/// A large, easy-to-hit arrow button.
func scArrow(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 30).background(Capsule().fill(Color.primary.opacity(0.1))).contentShape(Rectangle())
    }.buttonStyle(.plain).help(help)
}

private struct PanelCanvas: View {
    @ObservedObject var ui: SoccerUI
    @ObservedObject var store: SoccerStore
    var body: some View {
        VStack(spacing: 6) {
            topBar
            Group {
                switch ui.mode {
                case .matches: MatchesPage(ui: ui, store: store)
                default: CardsPage(ui: ui, store: store)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if ui.mode == .cards { bottomBar }
        }.padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            tab("My clubs", .cards)
            tab("Matches", .matches)
            Spacer()
            Button { ui.picker.searchActive = true; ui.mode = .picker } label: { Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).help("Search for a club")
            Button { ui.mode = .picker } label: { Image(systemName: "square.grid.3x3.fill").font(.system(size: 11)) }
                .buttonStyle(.plain).help("All 70 clubs: pick your favorites")
            Button { SoccerSettingsController.shared.show() } label: { Image(systemName: "gearshape").font(.system(size: 12)) }
                .buttonStyle(.plain).help("Soccer settings")
        }.frame(height: 22)
    }
    private func tab(_ title: String, _ mode: SoccerMode) -> some View {
        Button { ui.mode = mode } label: {
            Text(title).font(.system(size: 11, weight: ui.mode == mode ? .semibold : .regular)).padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(ui.mode == mode ? 0.18 : 0.06)))
        }.buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            scArrow("chevron.left", "Previous club") { ui.cardIndex = (ui.cardIndex - 1 + max(1, store.favorites.count)) % max(1, store.favorites.count) }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(store.favorites.enumerated()), id: \.offset) { i, key in
                    Button { ui.cardIndex = i } label: {
                        Circle().fill(Color.primary.opacity(i == ui.cardIndex % max(1, store.favorites.count) ? 0.85 : 0.22)).frame(width: 8, height: 8)
                            .frame(width: 16, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(store.team(key)?.name ?? key)
                }
            }
            Spacer()
            scArrow("chevron.right", "Next club") { ui.cardIndex = (ui.cardIndex + 1) % max(1, store.favorites.count) }
        }.frame(height: 30).opacity(store.favorites.count > 1 ? 1 : 0)
    }
}

// MARK: - My clubs (rotating cards)

private struct CardsPage: View {
    @ObservedObject var ui: SoccerUI
    @ObservedObject var store: SoccerStore
    var body: some View {
        if store.favorites.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "soccerball").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Pick your clubs").font(.headline)
                Text("Premier League, La Liga and MLS. Choose favorites and their matches rotate here, live.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Choose clubs") { ui.mode = .picker }.buttonStyle(.borderedProminent).controlSize(.small)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { cards }
    }
    @ViewBuilder private var cards: some View {
        let key = ui.celebration?.team ?? store.favorites[ui.cardIndex % store.favorites.count]
        if let match = store.currentMatch(for: key).map({ store.fresh($0) }) {
            MatchCard(match: match, focus: key, celebrate: ui.celebration?.team, showLeague: false)
                .overlay(alignment: .top) { if let c = ui.celebration { CelebrationBanner(info: c).transition(.scale(scale: 0.6).combined(with: .opacity)) } }
                .contentShape(Rectangle())
                .onTapGesture { SoccerDetailsController.shared.show(team: key, match: match) }
                .onHover { ui.hoveringCard = $0 }
                .help("Click for results, the table and stats")
                .id(key + match.id)
                .transition(.opacity)
        } else {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(store.offline ? "Can't reach the score feed right now." : "Loading \(store.team(key)?.name ?? "your club")…").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The banner across the top of a card when someone has just scored.
private struct CelebrationBanner: View {
    let info: ScoreAlertInfo
    @ObservedObject var store = SoccerStore.shared
    @State private var pulse = false
    var body: some View {
        let color = store.team(info.team)?.color ?? .orange
        HStack(spacing: 6) {
            Image(systemName: info.kind == "RED CARD" ? "rectangle.portrait.fill" : "soccerball")
            Text(info.kind).font(.system(size: 14, weight: .heavy)).tracking(1.2)
            Text((store.team(info.team)?.short ?? "").uppercased()).font(.system(size: 11, weight: .bold)).opacity(0.9).lineLimit(1)
        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(color).shadow(color: color.opacity(0.7), radius: pulse ? 10 : 3))
        .scaleEffect(pulse ? 1.05 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - The match card

struct MatchCard: View {
    let match: Match
    var focus: String?
    var celebrate: String?
    var showLeague = true
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        VStack(spacing: 6) {
            statusRow
            HStack(alignment: .top, spacing: 0) {
                ClubBlock(key: match.home, match: match, focus: focus, celebrate: celebrate)
                scoreView.frame(maxWidth: .infinity)
                ClubBlock(key: match.away, match: match, focus: focus, celebrate: celebrate)
            }
            HalfBar(match: match)
            EventList(match: match)
            if match.state == .pre { Text([match.venue, match.broadcast].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            if match.state == .live && !match.isDelayed && !match.isHalftime { Circle().fill(Color.red).frame(width: 7, height: 7) }
            Text(match.state == .pre ? "\(match.statusLine)\(countdown)" : match.statusLine)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(match.state == .live ? Color.red : .primary)
            Spacer()
            if showLeague { LeagueMark(league: League.named(match.league), size: 15, showName: true) }
        }
    }
    private var countdown: String {
        let s = match.date.timeIntervalSinceNow
        guard s > 0, s < 48 * 3600 else { return "" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "  ·  in \(h)h \(m)m" : "  ·  in \(m)m"
    }
    @ViewBuilder private var scoreView: some View {
        if match.state == .pre {
            Text("v").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).padding(.top, 14)
        } else {
            HStack(spacing: 8) {
                Text("\(match.homeScore)").foregroundStyle(dim(match.home))
                Text("–").foregroundStyle(.secondary)
                Text("\(match.awayScore)").foregroundStyle(dim(match.away))
            }.font(.system(size: 30, weight: .heavy).monospacedDigit()).padding(.top, 8)
        }
    }
    private func dim(_ key: String) -> Color {
        guard match.state == .post, match.homeScore != match.awayScore else { return .primary }
        return match.score(of: key) > match.score(of: match.opponent(of: key)) ? .primary : .secondary
    }
}

private struct ClubBlock: View {
    let key: String
    let match: Match
    var focus: String?
    var celebrate: String?
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let team = store.team(key)
        let tid = match.teamID(for: key)
        let yellow = match.cards(for: tid, red: false), red = match.cards(for: tid, red: true)
        VStack(spacing: 2) {
            TeamLogo(key: key, size: 52)
                .shadow(color: celebrate == key ? (team?.color ?? .white) : .clear, radius: 12)
                .scaleEffect(celebrate == key ? 1.12 : 1)
                .padding(3)
            Text(team?.short ?? "Club").font(.system(size: 11, weight: key == focus ? .bold : .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 3) {
                ForEach(0..<min(yellow, 4), id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 1, green: 0.84, blue: 0.1)).frame(width: 7, height: 10) }
                ForEach(0..<min(red, 3), id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.95, green: 0.2, blue: 0.2)).frame(width: 7, height: 10) }
            }.frame(height: 10)
        }.frame(width: 90)
    }
}

/// The clock for the half being played: a bar from 0' to 45' (then 45' to 90'), with a soccer ball rolling along it.
struct HalfBar: View {
    let match: Match
    var body: some View {
        let p = match.halfProgress
        let (startLabel, endLabel): (String, String) = match.half == 2 ? ("45'", "90'") : match.half >= 3 ? ("90'", "120'") : ("0'", "45'")
        let title = match.state == .pre ? "Kick-off" : match.state == .post ? "Full time" : match.isHalftime ? "Half-time" : match.half == 1 ? "1st half" : match.half == 2 ? "2nd half" : "Extra time"
        VStack(spacing: 1) {
            GeometryReader { proxy in
                let w = proxy.size.width, x = max(8, min(w - 8, w * p))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14)).frame(height: 6)
                    Capsule().fill(match.state == .live ? Color.white : Color.primary.opacity(0.45)).frame(width: max(6, x), height: 6)
                    Image(systemName: "soccerball").font(.system(size: 16)).foregroundStyle(.white)
                        .background(Circle().fill(Color.black.opacity(0.35)).frame(width: 15, height: 15))
                        .rotationEffect(.degrees(p * 720))
                        .shadow(radius: 2)
                        .opacity(match.state == .pre ? 0.55 : 1)
                        .position(x: x, y: 8)
                    if let plus = match.stoppage {
                        Text(plus).font(.system(size: 9, weight: .heavy)).foregroundStyle(.orange).padding(.horizontal, 4).background(Capsule().fill(Color.black.opacity(0.5)))
                            .position(x: max(20, w - 18), y: -4)
                    }
                }.frame(height: 16)
            }.frame(height: 16)
            HStack {
                Text(startLabel).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text(title).font(.system(size: 9, weight: match.state == .live ? .bold : .regular)).foregroundStyle(match.state == .live ? Color.primary : .secondary)
                Spacer()
                Text(endLabel).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Goals (with the scorer and minute) and cards, newest last; the home side reads on the left, the away side on the right.
struct EventList: View {
    let match: Match
    var limit = 4
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let shown = Array(match.events.sorted { $0.seconds < $1.seconds }.suffix(limit))
        if match.state != .pre && !shown.isEmpty {
            VStack(spacing: 2) {
                ForEach(shown) { e in
                    let home = e.kind == .ownGoal ? e.teamID != match.homeID : e.teamID == match.homeID
                    HStack(spacing: 4) {
                        if home { icon(e); Text(e.text).font(.system(size: 10.5, weight: e.isGoal ? .semibold : .regular)).lineLimit(1); Spacer(minLength: 0) }
                        else { Spacer(minLength: 0); Text(e.text).font(.system(size: 10.5, weight: e.isGoal ? .semibold : .regular)).lineLimit(1); icon(e) }
                    }
                }
            }
        } else if match.state != .pre {
            Text("No goals or cards yet").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func icon(_ e: MatchEvent) -> some View {
        switch e.kind {
        case .yellow: RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 1, green: 0.84, blue: 0.1)).frame(width: 8, height: 11)
        case .red: RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.95, green: 0.2, blue: 0.2)).frame(width: 8, height: 11)
        default: Image(systemName: "soccerball").font(.system(size: 11))
        }
    }
}

// MARK: - Matches (an agenda of every game in all three leagues)

private struct MatchesPage: View {
    @ObservedObject var ui: SoccerUI
    @ObservedObject var store: SoccerStore
    private var leagues: [League] { ui.leagueFilter.map { [League.named($0)] } ?? League.all }
    private func date(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date() }
    private func matches(_ offset: Int) -> [Match] {
        leagues.flatMap { store.day(date(offset), league: $0.code) }.sorted { ($0.state == .live ? 0 : 1, $0.date) < ($1.state == .live ? 0 : 1, $1.date) }
    }
    /// The first day from today on that has games, so the list opens on something real.
    private var firstOffset: Int? { (0..<ui.daysAhead).first { !matches($0).isEmpty } }
    var body: some View {
        let pending = store.pendingDays(-ui.pastDays..<ui.daysAhead, leagues: leagues)
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                chip("All", nil)
                ForEach(League.all) { chip($0.short, $0.code) }
                Spacer()
                if pending > 0 { ProgressView().controlSize(.mini) }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        Button("Earlier days") { ui.pastDays += 7; load() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(Array((-ui.pastDays..<ui.daysAhead)), id: \.self) { off in
                            let list = matches(off)
                            if !list.isEmpty {
                                HStack {
                                    Text(off == 0 ? "Today" : date(off).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text("\(list.count) match\(list.count == 1 ? "" : "es")").font(.system(size: 9)).foregroundStyle(.secondary)
                                }.padding(.top, 4).id(off)
                                ForEach(list) { MatchRow(match: store.fresh($0)) }
                            }
                        }
                        if pending == 0 && !(-ui.pastDays..<ui.daysAhead).contains(where: { !matches($0).isEmpty }) {
                            Text(store.offline ? "Can't reach the score feed right now." : "No matches in this stretch.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 20)
                        }
                        Button("Show next week") { ui.daysAhead += 7; load() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).padding(.vertical, 4)
                    }
                }
                .onAppear { load(); if let f = firstOffset { proxy.scrollTo(f, anchor: .top) } }
                .onChange(of: firstOffset) { _, f in if let f, ui.pastDays == 0 { proxy.scrollTo(f, anchor: .top) } }
            }
        }
    }
    private func chip(_ title: String, _ code: String?) -> some View {
        Button { ui.leagueFilter = code; load() } label: {
            Text(title).font(.system(size: 10, weight: ui.leagueFilter == code ? .semibold : .regular)).padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(ui.leagueFilter == code ? 0.2 : 0.07)))
        }.buttonStyle(.plain)
    }
    private func load() { store.loadRange(-ui.pastDays..<ui.daysAhead, leagues: leagues) }
}

private struct MatchRow: View {
    let match: Match
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let mine = store.favorites.contains { match.involves($0) }
        HStack(spacing: 5) {
            LeagueMark(league: League.named(match.league), size: 14, showFlag: false).help(League.named(match.league).name)
            side(match.home, match.homeScore)
            Text("v").font(.system(size: 9)).foregroundStyle(.secondary)
            side(match.away, match.awayScore)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                if match.state == .live { Circle().fill(Color.red).frame(width: 6, height: 6) }
                Text(match.statusLine).font(.system(size: 10, weight: match.state == .live ? .semibold : .regular)).foregroundStyle(match.state == .live ? Color.red : .secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 6).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(mine ? Color(red: 1, green: 0.84, blue: 0.04).opacity(0.16) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { SoccerDetailsController.shared.show(team: store.favorites.first { match.involves($0) } ?? match.home, match: match) }
        .help("Double-click for the match details")
    }
    private func side(_ key: String, _ score: Int) -> some View {
        HStack(spacing: 3) {
            TeamLogo(key: key, size: 20)
            Text(store.team(key)?.abbr ?? "?").font(.system(size: 11, weight: .semibold))
            if store.favorites.contains(key) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
            if match.state != .pre { Text("\(score)").font(.system(size: 12, weight: .bold).monospacedDigit()) }
        }
    }
}

/// The league's logo, flag and name (all in white) in the empty space of the zone below the card, so you can see at a glance
/// which league you're looking at. With no single league (the Matches tab on "All") it shows all three logos and flags.
struct LeagueBadge: View {
    let codes: [String]
    let size: CGFloat
    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(codes, id: \.self) { code in
                let league = League.named(code)
                HStack(spacing: size * 0.22) {
                    LeagueMark(league: league, size: size, showFlag: false)
                    Text(league.flag).font(.system(size: size * 0.85))
                    if codes.count == 1 { Text(league.name).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1) }
                }
            }
        }.shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
    static func estimatedWidth(codes: [String], size: CGFloat) -> CGFloat {
        codes.reduce(CGFloat(0)) { total, code in
            total + size + size * 0.22 + size * 0.85 * 1.15 + (codes.count == 1 ? size * 0.22 + CGFloat(League.named(code).name.count) * size * 0.31 : 0) + size * 0.35
        }
    }
    /// The biggest badge that fits in the free space of the shape (anywhere the card isn't), and where it goes. Among the spots that fit
    /// the biggest size, it takes the one nearest the rim on the side the zone faces.
    static func spot(geo: FGeo, rect: CGRect, codes: [String]) -> (size: CGFloat, center: CGPoint)? {
        let target = geo.point(geo.radius * 0.84, geo.facing)
        let keepOut = rect.insetBy(dx: -4, dy: -4)
        // Half circles (top, bottom, left, right): the tip of the circle, centred on the middle line, just past the card.
        if !geo.isCorner && !geo.full {
            let dir = CGPoint(x: cos(geo.facing), y: sin(geo.facing))
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            let far = corners.map { ($0.x - geo.anchor.x) * dir.x + ($0.y - geo.anchor.y) * dir.y }.max() ?? 0
            var tipSize: CGFloat = 46
            while tipSize >= 18 {
                let w = estimatedWidth(codes: codes, size: tipSize), h = tipSize + 6
                var d = geo.radius * 0.97 - h / 2
                while d >= far + h / 2 + 2 {
                    let c = CGPoint(x: geo.anchor.x + dir.x * d, y: geo.anchor.y + dir.y * d)
                    let box = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                    let inside = [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)].allSatisfy { p in
                        hypot(p.0 - geo.anchor.x, p.1 - geo.anchor.y) <= geo.radius * 0.955 && p.0 >= 4 && p.1 >= 4 && p.0 <= geo.size.width - 4 && p.1 <= geo.size.height - 4
                    }
                    if inside && !box.intersects(keepOut) { return (tipSize, c) }
                    d -= 3
                }
                tipSize -= 4
            }
        }
        var size: CGFloat = 60
        while size >= 22 {
            let w = estimatedWidth(codes: codes, size: size), h = size + 6
            var best: (center: CGPoint, distance: CGFloat)?
            for x in stride(from: w / 2 + 6, through: geo.size.width - w / 2 - 6, by: 10) {
                for y in stride(from: h / 2 + 6, through: geo.size.height - h / 2 - 6, by: 10) {
                    let box = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                    if box.intersects(keepOut) { continue }
                    let inside = [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)].allSatisfy { p in
                        hypot(p.0 - geo.anchor.x, p.1 - geo.anchor.y) <= geo.radius * 0.93
                    }
                    guard inside else { continue }
                    let d = hypot(x - target.x, y - target.y)
                    if best == nil || d < best!.distance { best = (CGPoint(x: x, y: y), d) }
                }
            }
            if let best { return (size, best.center) }
            size -= 6
        }
        return nil
    }
}
