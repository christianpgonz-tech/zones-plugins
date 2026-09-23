import AppKit
import SwiftUI

enum CollegeBasketballMode { case cards, games, picker }

final class CollegeBasketballUI: ObservableObject {
    init(mode: CollegeBasketballMode = .cards) { self.mode = mode }
    @Published var mode: CollegeBasketballMode
    @Published var cardIndex = 0
    @Published var dayOffset = 0                  // 0 = today
    @Published var filter = "all"                // all, top25 or mine
    let picker = PickerState()                    // the team picker's search and filter
    @Published var hoveringCard = false
    /// A score being celebrated on the card (the zone opened for it).
    @Published var celebration: ScoreAlertInfo?
}

/// Tells the wrapper view which points belong to the zone's content, so a press on empty space still reaches Zones
/// (that is how an open zone is picked up and moved).
final class CollegeBasketballHitMap { var contains: (CGPoint) -> Bool = { _ in true } }

final class CollegeBasketballPassThroughBox: NSView {
    let hit: CollegeBasketballHitMap
    init(hit: CollegeBasketballHitMap) { self.hit = hit; super.init(frame: .zero) }
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

struct CollegeBasketballView: View {
    let placement: String
    let hit: CollegeBasketballHitMap
    @ObservedObject var store = CollegeBasketballStore.shared
    init(placement: String, hit: CollegeBasketballHitMap, startMode: CollegeBasketballMode = .cards) {
        self.placement = placement; self.hit = hit
        _ui = StateObject(wrappedValue: CollegeBasketballUI(mode: startMode))
    }
    @StateObject private var ui: CollegeBasketballUI
    private let design = CGSize(width: 320, height: 236)
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
                    if ui.mode != .picker, let spot = SportBadgeLayout.spot(geo: geo, rect: rect) {
                        SportBadge(title: "College Basketball", size: spot.size) {
                            if let icon = CollegeBasketballIcon.image { Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit() }
                            else { Image(systemName: "basketball.fill").resizable().scaledToFit() }
                        }.position(spot.center).allowsHitTesting(false)
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
            // Someone scored: show that game's card with a celebration banner for as long as the alert setting says.
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

private struct PanelCanvas: View {
    @ObservedObject var ui: CollegeBasketballUI
    @ObservedObject var store: CollegeBasketballStore
    var body: some View {
        VStack(spacing: 6) {
            topBar
            Group {
                switch ui.mode {
                case .games: GamesPage(ui: ui, store: store)
                default: CardsPage(ui: ui, store: store)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if ui.mode == .cards { bottomBar }
        }.padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            tab("My teams", .cards)
            tab("Games", .games)
            Spacer()
            Button { ui.picker.searchActive = true; ui.mode = .picker } label: { Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).help("Search for a school")
            Button { ui.mode = .picker } label: { Image(systemName: "square.grid.3x3.fill").font(.system(size: 11)) }
                .buttonStyle(.plain).help("Every Division I school: pick your favorites")
            Button { CollegeBasketballSettingsController.shared.show() } label: { Image(systemName: "gearshape").font(.system(size: 12)) }
                .buttonStyle(.plain).help("College Basketball settings")
        }.frame(height: 22)
    }
    private func tab(_ title: String, _ mode: CollegeBasketballMode) -> some View {
        Button { ui.mode = mode } label: {
            Text(title).font(.system(size: 11, weight: ui.mode == mode ? .semibold : .regular)).padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(ui.mode == mode ? 0.18 : 0.06)))
        }.buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            scArrow("chevron.left", "Previous school") { ui.cardIndex = (ui.cardIndex - 1 + max(1, store.favorites.count)) % max(1, store.favorites.count) }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(store.favorites.enumerated()), id: \.offset) { i, abbr in
                    Button { ui.cardIndex = i } label: {
                        Circle().fill(Color.primary.opacity(i == ui.cardIndex % max(1, store.favorites.count) ? 0.85 : 0.22)).frame(width: 8, height: 8)
                            .frame(width: 16, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(store.team(abbr)?.name ?? abbr)
                }
            }
            Spacer()
            scArrow("chevron.right", "Next school") { ui.cardIndex = (ui.cardIndex + 1) % max(1, store.favorites.count) }
        }.frame(height: 30).opacity(store.favorites.count > 1 ? 1 : 0)
    }
}

// MARK: - My teams (rotating cards)

private struct CardsPage: View {
    @ObservedObject var ui: CollegeBasketballUI
    @ObservedObject var store: CollegeBasketballStore
    var body: some View {
        if store.favorites.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "basketball.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Pick your schools").font(.headline)
                Text("Pick your favorite schools and their games rotate here, live.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Choose schools") { ui.mode = .picker }.buttonStyle(.borderedProminent).controlSize(.small)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { cards }
    }
    @ViewBuilder private var cards: some View {
        let abbr = ui.celebration?.team ?? store.favorites[ui.cardIndex % store.favorites.count]
        if let game = store.currentGame(for: abbr) {
            GameCard(game: game, focus: abbr, celebrate: ui.celebration?.team)
                .overlay(alignment: .top) { if let c = ui.celebration { CelebrationBanner(info: c).transition(.scale(scale: 0.6).combined(with: .opacity)) } }
                .contentShape(Rectangle())
                .onTapGesture { CollegeBasketballDetailsController.shared.show(team: abbr, game: game) }
                .onHover { ui.hoveringCard = $0 }
                .help("Click for the season, standings and rankings")
                .id(abbr + game.id)
                .transition(.opacity)
        } else {
            VStack(spacing: 6) {
                if store.schedules[abbr] == nil { ProgressView().controlSize(.small) }
                Text(store.offline ? "Can't reach the score feed right now." : store.schedules[abbr] != nil ? "No games scheduled right now." : "Loading \(store.team(abbr)?.name ?? abbr)…").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The banner across the top of a card when someone has just scored.
private struct CelebrationBanner: View {
    let info: ScoreAlertInfo
    @ObservedObject var store = CollegeBasketballStore.shared
    @State private var pulse = false
    var body: some View {
        let color = store.team(info.team)?.color ?? .orange
        HStack(spacing: 6) {
            Image(systemName: "basketball.fill")
            Text(info.kind).font(.system(size: 14, weight: .heavy)).tracking(1.2)
            Text(store.team(info.team)?.school.uppercased() ?? info.team).font(.system(size: 11, weight: .bold)).opacity(0.9)
        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(color).shadow(color: color.opacity(0.7), radius: pulse ? 10 : 3))
        .scaleEffect(pulse ? 1.05 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct GameCard: View {
    let game: Game
    var focus: String?
    var celebrate: String?
    @ObservedObject var store = CollegeBasketballStore.shared
    var body: some View {
        VStack(spacing: 7) {
            statusRow
            HStack(alignment: .top, spacing: 0) {
                TeamBlock(abbr: game.away, game: game, focus: focus, celebrate: celebrate)
                scoreView.frame(maxWidth: .infinity)
                TeamBlock(abbr: game.home, game: game, focus: focus, celebrate: celebrate)
            }
            TimeBar(game: game)
            if game.state == .live { situation }
            else { footer }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            if game.state == .live && !game.isDelayed { Circle().fill(Color.red).frame(width: 7, height: 7) }
            Text(game.state == .pre ? "\(game.statusLine)\(countdown)" : game.statusLine)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(game.state == .live ? Color.red : .primary)
            Spacer()
            Text("\(Game.day.string(from: game.date))\(game.broadcast.map { " · \($0)" } ?? "")").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    private var countdown: String {
        let s = game.date.timeIntervalSinceNow
        guard s > 0, s < 48 * 3600 else { return "" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "  ·  in \(h)h \(m)m" : "  ·  in \(m)m"
    }
    @ViewBuilder private var scoreView: some View {
        if game.state == .pre {
            Text("vs").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).padding(.top, 14)
        } else {
            HStack(spacing: 8) {
                Text("\(game.awayScore)").lineLimit(1).fixedSize().foregroundStyle(dim(game.away))
                Text("–").foregroundStyle(.secondary)
                Text("\(game.homeScore)").lineLimit(1).fixedSize().foregroundStyle(dim(game.home))
            }.font(.system(size: 30, weight: .heavy).monospacedDigit()).padding(.top, 8)
        }
    }
    private func dim(_ abbr: String) -> Color {
        guard game.state == .post, game.awayScore != game.homeScore else { return .primary }
        let won = game.score(of: abbr) > game.score(of: game.opponent(of: abbr))
        return won ? .primary : .secondary
    }

    private var situation: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if game.isClutch { Text("CLOSE GAME").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.red)) }
                Text(game.venue ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            MarginBar(game: game)
        }
    }
    private var footer: some View {
        VStack(spacing: 2) {
            if game.state == .pre {
                Text(game.venue ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Click for the season, standings and rankings").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Who is ahead and by how much: the bar tips toward the team in front.
private struct MarginBar: View {
    let game: Game
    @ObservedObject var store = CollegeBasketballStore.shared
    var body: some View {
        GeometryReader { proxy in
            let diff = Double(game.homeScore - game.awayScore), span = min(1, abs(diff) / 20) * 0.5
            let mid = proxy.size.width / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill((diff >= 0 ? store.team(game.home)?.color : store.team(game.away)?.color) ?? .gray)
                    .frame(width: max(3, proxy.size.width * span)).offset(x: diff >= 0 ? mid : mid - proxy.size.width * span)
                Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1.5).offset(x: mid - 0.75)
            }
        }.frame(height: 7)
    }
}

private struct TeamBlock: View {
    let abbr: String
    let game: Game
    var focus: String?
    var celebrate: String?
    @ObservedObject var store = CollegeBasketballStore.shared
    var body: some View {
        let hasBall = false
        let team = store.team(abbr)
        let record = abbr == game.away ? game.awayRecord : game.homeRecord
        let leader = abbr == game.away ? game.awayLeader : game.homeLeader
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                TeamLogo(abbr: abbr, size: 52)
                    .shadow(color: celebrate == abbr ? (team?.color ?? .white) : .clear, radius: 12)
                    .scaleEffect(celebrate == abbr ? 1.12 : 1)
                    .padding(3)
                    .background(Circle().stroke(hasBall ? Color.white : Color.clear, lineWidth: 2))
                if hasBall {
                    Image(systemName: "basketball.fill").font(.system(size: 11)).foregroundStyle(.white)
                        .padding(4).background(Circle().fill(Color(red: 0.55, green: 0.29, blue: 0.1))).offset(x: 4, y: 2)
                }
            }
            HStack(spacing: 3) {
                RankTag(rank: abbr == game.away ? game.awayRank : game.homeRank, size: 9)
                Text(team?.school ?? abbr).font(.system(size: 11, weight: abbr == focus ? .bold : .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                if store.favorites.contains(abbr) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
            }
            Text(record ?? " ").font(.system(size: 9)).foregroundStyle(.secondary)
            Text((game.state == .pre ? nil : leader) ?? " ").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(width: 90)
    }
}

/// One segment per period (quarter, half or inning) that fills as the game runs, with a marker at the current moment; overtime adds a badge.
struct TimeBar: View {
    let game: Game
    var body: some View {
        let n = CollegeBasketballSport.regulation
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let gap: CGFloat = n > 4 ? 2 : 3, w = (proxy.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(0..<n, id: \.self) { i in
                            let fill = max(0, min(1, game.progress * Double(n) - Double(i)))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.14))
                                Capsule().fill(game.state == .live ? Color.white : Color.primary.opacity(0.45)).frame(width: max(0, w * fill))
                            }.frame(width: w)
                        }
                    }
                    if game.state == .live {
                        let q = min(n - 1, Int(game.progress * Double(n)))
                        let x = Double(q) * (w + gap) + w * max(0, min(1, game.progress * Double(n) - Double(q)))
                        Circle().fill(Color.white).frame(width: 9, height: 9).shadow(radius: 2).offset(x: x - 4.5)
                    }
                }.frame(height: 9)
            }.frame(height: 9)
            HStack {
                ForEach(1...n, id: \.self) { q in
                    Text(CollegeBasketballSport.periodNames[q - 1]).font(.system(size: 8, weight: game.state == .live && game.period == q ? .bold : .regular))
                        .foregroundStyle(game.state == .live && game.period == q ? Color.primary : .secondary).frame(maxWidth: .infinity)
                }
                if game.period > n { Text(CollegeBasketballSport.extraLabel).font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
            }
        }
    }
}

// MARK: - Games (every game of a day)

private struct GamesPage: View {
    @ObservedObject var ui: CollegeBasketballUI
    @ObservedObject var store: CollegeBasketballStore
    private var day: Int { ui.dayOffset }
    private var dayDate: Date { Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date() }
    private func games() -> [Game] {
        store.board(day: day).filter { g in
            switch ui.filter {
            case "top25": return g.homeRank != nil || g.awayRank != nil
            case "mine": return store.favorites.contains { g.involves($0) }
            default: return true
            }
        }.sorted { ($0.state == .live ? 0 : $0.state == .pre ? 1 : 2, $0.date, $0.homeRank ?? 99) < ($1.state == .live ? 0 : $1.state == .pre ? 1 : 2, $1.date, $1.homeRank ?? 99) }
    }
    private var title: String {
        switch day { case 0: return "Today"; case -1: return "Yesterday"; case 1: return "Tomorrow"; default: return Game.day.string(from: dayDate) }
    }
    var body: some View {
        let list = games()
        VStack(spacing: 6) {
            HStack {
                scArrow("chevron.left", "Earlier day") { go(-1) }.disabled(day <= -30)
                Spacer()
                VStack(spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text("\(store.board(day: day).count) games").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if day != 0 { Button("Today") { ui.dayOffset = 0; store.loadDay(0) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                scArrow("chevron.right", "Later day") { go(1) }.disabled(day >= 30)
            }
            HStack(spacing: 4) {
                chip("All", "all"); chip("Top 25", "top25"); chip("My teams", "mine")
                Spacer()
            }
            if list.isEmpty {
                Text(store.board(day: day).isEmpty ? (store.offline ? "Can't reach the score feed right now." : "No games, or still loading…") : "No games match this filter.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(sections(list), id: \.0) { name, items in
                            HStack {
                                Text(name).font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text("\(items.count) game\(items.count == 1 ? "" : "s")").font(.system(size: 9)).foregroundStyle(.secondary)
                            }.padding(.top, 4)
                            ForEach(items) { GameRow(game: $0) }
                        }
                    }
                }
            }
        }.onAppear { store.loadDay(day) }
    }
    /// Live games first, then the ones still to play, then the finished ones.
    private func sections(_ list: [Game]) -> [(String, [Game])] {
        [("Live now", list.filter { $0.state == .live }), ("Upcoming", list.filter { $0.state == .pre }), ("Final", list.filter { $0.state == .post })].filter { !$0.1.isEmpty }
    }
    private func chip(_ title: String, _ value: String) -> some View {
        Button { ui.filter = value } label: {
            Text(title).font(.system(size: 10, weight: ui.filter == value ? .semibold : .regular)).padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(ui.filter == value ? 0.2 : 0.07)))
        }.buttonStyle(.plain)
    }
    private func go(_ d: Int) {
        ui.dayOffset = max(-30, min(30, day + d))
        store.loadDay(ui.dayOffset)
    }
}

private struct GameRow: View {
    let game: Game
    @ObservedObject var store = CollegeBasketballStore.shared
    var body: some View {
        let mine = store.favorites.contains { game.involves($0) }
        HStack(spacing: 5) {
            side(game.away, game.awayScore, game.awayRank)
            Text("@").font(.system(size: 9)).foregroundStyle(.secondary)
            side(game.home, game.homeScore, game.homeRank)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                if game.state == .live { Circle().fill(Color.red).frame(width: 6, height: 6) }
                Text(game.statusLine).font(.system(size: 10, weight: game.state == .live ? .semibold : .regular)).foregroundStyle(game.state == .live ? Color.red : .secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 6).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(mine ? Color(red: 1, green: 0.84, blue: 0.04).opacity(0.16) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { CollegeBasketballDetailsController.shared.show(team: store.favorites.first { game.involves($0) } ?? game.home, game: game) }
        .help("Double-click for the game details")
    }
    private func side(_ abbr: String, _ score: Int, _ rank: Int?) -> some View {
        HStack(spacing: 3) {
            TeamLogo(abbr: abbr, size: 20)
            RankTag(rank: rank, size: 8)
            Text(abbr).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if store.favorites.contains(abbr) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
            if game.state != .pre { Text("\(score)").font(.system(size: 12, weight: .bold).monospacedDigit()) }
        }
    }
}

/// The helmet logo (from the zone's bundle) used as the badge and handle icon.
enum CollegeBasketballIcon {
    static let image: NSImage? = {
        guard let url = Bundle(for: CollegeBasketballZone.self).url(forResource: "ZoneIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// A large, easy-to-hit arrow button.
func scArrow(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 30).background(Capsule().fill(Color.primary.opacity(0.1))).contentShape(Rectangle())
    }.buttonStyle(.plain).help(help)
}
