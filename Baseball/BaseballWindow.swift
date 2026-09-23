import AppKit
import SwiftUI

// MARK: - Details window (double-click or click a card)

/// Season scores, conference standings, the AP Top 25, school stats and the live game, in a window that stays open and
/// remembers its size and place.
final class BaseballDetailsController {
    static let shared = BaseballDetailsController()
    private var window: NSWindow?
    let selection = BaseballSelection()

    func show(team: String, game: Game?) {
        selection.team = team
        selection.gameID = game?.id
        selection.tab = game?.state == .live ? .live : .scores
        BaseballStore.shared.loadSchedule(team)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "MLB Baseball"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.minSize = NSSize(width: 740, height: 540)
            w.contentView = NSHostingView(rootView: DetailsView(selection: selection))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("BaseballDetailsWindow") { w.center() }
            w.setFrameAutosaveName("BaseballDetailsWindow")
            window = w
        }
        BaseballStore.shared.refreshBoard()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum BaseballTab: String, CaseIterable, Identifiable { case scores = "Season", standings = "Standings", stats = "Team stats", live = "Live game"; var id: String { rawValue } }

final class BaseballSelection: ObservableObject {
    @Published var team = ""
    @Published var gameID: String?
    @Published var tab: BaseballTab = .scores
}

struct DetailsView: View {
    @ObservedObject var selection: BaseballSelection
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        let team = store.team(selection.team)
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TeamLogo(abbr: selection.team, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) { RankTag(rank: store.rank(of: selection.team), size: 16); Text(team?.name ?? selection.team).font(.title2.weight(.semibold)) }
                    Text("\(team?.conference ?? "")  ·  \(store.standing(for: selection.team).map { "\($0.overall), \($0.gb) GB" } ?? "")").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !store.favorites.isEmpty {
                        Section("My teams") { ForEach(store.favorites, id: \.self) { a in Button(store.team(a)?.school ?? a) { pick(a) } } }
                    }
                    ForEach(store.conferences, id: \.self) { c in Menu(c) { ForEach(store.teams(in: c)) { t in Button(t.school) { pick(t.abbr) } } } }
                } label: { Label("Change team", systemImage: "arrow.left.arrow.right") }.fixedSize()
                Button { store.refreshBoard(); store.loadSchedule(selection.team) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh now")
            }
            Picker("", selection: $selection.tab) { ForEach(BaseballTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch selection.tab {
                case .scores: SeasonTab(team: selection.team, selection: selection)
                case .standings: StandingsTab(selected: selection.team, selection: selection)
                case .stats: StatsTab(team: selection.team)
                case .live: LiveTab(team: selection.team, gameID: selection.gameID)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(store.offline ? "Offline: showing saved data." : (store.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                Spacer()
                Text("Unofficial. Not affiliated with Major League Baseball or any team. Data: ESPN's public ESPN's public MLB feed.")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func pick(_ abbr: String) { selection.team = abbr; store.loadSchedule(abbr); selection.gameID = store.currentGame(for: abbr)?.id }
}

extension BaseballSelection {
    /// Switches the whole window to another school, on its season page.
    func open(_ abbr: String) {
        team = abbr
        BaseballStore.shared.loadSchedule(abbr)
        gameID = BaseballStore.shared.currentGame(for: abbr)?.id
        tab = .scores
    }
}

// MARK: Season (every game of a school)

private struct SeasonTab: View {
    let team: String
    @ObservedObject var selection: BaseballSelection
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        let games = store.games(for: team)
        if games.isEmpty { Text("Loading the schedule…").foregroundStyle(.secondary) }
        else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(games) { g in
                        let opp = g.opponent(of: team), home = g.home == team
                        HStack(spacing: 12) {
                            Text(Game.dayShort.string(from: g.date)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                            Text(home ? "vs" : "@").foregroundStyle(.secondary).frame(width: 20)
                            TeamLogo(abbr: opp, size: 28)
                            HStack(spacing: 5) {
                                RankTag(rank: g.rank(of: opp), size: 10)
                                Text(store.team(opp)?.name ?? opp)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            resultView(g)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 9).fill(g.state == .live ? Color.red.opacity(0.12) : Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                        .onTapGesture { selection.gameID = g.id; selection.tab = .live }
                    }
                }
            }
        }
    }
    @ViewBuilder private func resultView(_ g: Game) -> some View {
        switch g.state {
        case .pre: Text(Game.kickoff.string(from: g.date)).foregroundStyle(.secondary).frame(width: 190, alignment: .trailing)
        case .live: Text("LIVE  \(g.statusLine)  \(g.score(of: team))–\(g.score(of: g.opponent(of: team)))").foregroundStyle(.red).fontWeight(.semibold).frame(width: 190, alignment: .trailing)
        case .post:
            let mine = g.score(of: team), theirs = g.score(of: g.opponent(of: team))
            HStack(spacing: 6) {
                Text(mine > theirs ? "W" : mine < theirs ? "L" : "T").fontWeight(.bold).foregroundStyle(mine > theirs ? Color.green : mine < theirs ? Color.red : .secondary)
                Text("\(mine)–\(theirs)").monospacedDigit()
                if g.overtime { Text("F/\(g.period)").font(.caption).foregroundStyle(.orange) }
            }.frame(width: 190, alignment: .trailing)
        }
    }
}

// MARK: Conference standings

private struct StandingsTab: View {
    let selected: String
    @ObservedObject var selection: BaseballSelection
    @State private var conference: String?
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        let current = conference ?? store.team(selected)?.conference ?? store.conferences.first ?? "SEC"
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.conferences, id: \.self) { c in
                        Button { conference = c } label: {
                            Text(c).font(.callout.weight(c == current ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(c == current ? 0.2 : 0.07)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            ScrollView {
                VStack(spacing: 2) {
                    HStack {
                        Text("").frame(width: 24)
                        Text("").frame(maxWidth: .infinity)
                        ForEach(["W-L", "Pct", "GB", "L10", "Diff", "Strk"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(width: 52) }
                    }
                    let rows = store.standings.first { $0.name == current }?.rows ?? []
                    if rows.isEmpty { Text("Loading the standings…").foregroundStyle(.secondary).padding() }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack {
                            Text("\(i + 1)").frame(width: 24).foregroundStyle(.secondary)
                            TeamLogo(abbr: r.team, size: 22)
                            HStack(spacing: 4) {
                                RankTag(rank: store.rank(of: r.team), size: 9)
                                Text(store.team(r.team)?.school ?? r.team).lineLimit(1).fontWeight(store.favorites.contains(r.team) || r.team == selected ? .bold : .regular)
                                if store.favorites.contains(r.team) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(r.overall).frame(width: 52); Text(r.pct).frame(width: 52); Text(r.gb).frame(width: 52); Text(r.l10).frame(width: 52)
                            Text(r.diff > 0 ? "+\(r.diff)" : "\(r.diff)").foregroundStyle(r.diff > 0 ? Color.green : r.diff < 0 ? Color.red : .secondary).frame(width: 52)
                            Text(r.streak).frame(width: 52)
                        }.font(.callout.monospacedDigit()).padding(.vertical, 3).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(r.team == selected ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { selection.open(r.team) }
                        .help("Double-click for this team's details")
                    }
                }
            }
        }
    }
}

// MARK: AP Top 25

private struct Top25Tab: View {
    @ObservedObject var selection: BaseballSelection
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        if store.top25.isEmpty { Text("Loading the poll…").foregroundStyle(.secondary) }
        else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.top25) { r in
                        HStack(spacing: 12) {
                            Text("\(r.rank)").font(.title3.weight(.bold).monospacedDigit()).frame(width: 34)
                            TeamLogo(abbr: r.team, size: 30)
                            Text(store.team(r.team)?.name ?? r.team).fontWeight(store.favorites.contains(r.team) ? .bold : .regular)
                            if store.favorites.contains(r.team) { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
                            Spacer()
                            Text(store.team(r.team)?.conference ?? "").foregroundStyle(.secondary)
                            Text(r.record).font(.callout.monospacedDigit()).frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { selection.open(r.team) }
                        .help("Double-click for this team's details")
                    }
                    Text("AP Top 25 poll").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
    }
}

// MARK: School stats

private struct StatsTab: View {
    let team: String
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        if let s = store.standing(for: team) {
            let results = store.games(for: team).filter { $0.state == .post }
            let g = max(1, results.count)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        tile("Record", s.overall, "\(s.pct) win rate"); tile("Streak", s.streak)
                        tile("Runs scored", "\(s.pf)", String(format: "%.1f per game", Double(s.pf) / Double(g)))
                        tile("Runs allowed", "\(s.pa)", String(format: "%.1f per game", Double(s.pa) / Double(g)))
                        tile("Run differential", s.diff > 0 ? "+\(s.diff)" : "\(s.diff)")
                        tile("Home", record(results.filter { $0.home == team })); tile("Away", record(results.filter { $0.away == team }))
                        tile("Games back", s.gb); tile("Last 10", s.l10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last games").font(.headline)
                        HStack(spacing: 8) {
                            ForEach(Array(results.suffix(5).enumerated()), id: \.offset) { _, game in
                                let won = game.score(of: team) > game.score(of: game.opponent(of: team))
                                Text(won ? "W" : "L").font(.headline).frame(width: 34, height: 34).background(Circle().fill(won ? Color.green.opacity(0.7) : Color.red.opacity(0.7))).foregroundStyle(.white)
                            }
                            if results.isEmpty { Text("No games played yet.").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        } else { Text("Loading…").foregroundStyle(.secondary) }
    }
    private func record(_ list: [Game]) -> String {
        let w = list.filter { $0.score(of: team) > $0.score(of: $0.opponent(of: team)) }.count
        return "\(w)-\(list.count - w)"
    }
    private func tile(_ title: String, _ value: String, _ note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold).monospacedDigit())
            Text(note ?? " ").font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: Live game

private struct LiveTab: View {
    let team: String
    let gameID: String?
    @ObservedObject var store = BaseballStore.shared
    var body: some View {
        let found = store.currentBoard.first { $0.id == gameID } ?? store.games(for: team).first { $0.id == gameID } ?? store.currentGame(for: team)
        if let game = found {
            ScrollView {
                VStack(spacing: 16) {
                    GameCard(game: game, focus: team).frame(width: 320).scaleEffect(1.5).frame(width: 480, height: 340)
                    if let home = game.winProbHome, game.state == .live {
                        VStack(spacing: 4) {
                            Text("Win probability").font(.caption).foregroundStyle(.secondary)
                            GeometryReader { proxy in
                                HStack(spacing: 0) {
                                    Rectangle().fill(store.team(game.away)?.color ?? .gray).frame(width: proxy.size.width * (1 - home))
                                    Rectangle().fill(store.team(game.home)?.color ?? .gray)
                                }.clipShape(Capsule())
                            }.frame(width: 360, height: 12)
                            HStack { Text("\(game.away) \(Int((1 - home) * 100))%"); Spacer(); Text("\(game.home) \(Int(home * 100))%") }.font(.caption).frame(width: 360)
                        }
                    }
                    if let play = game.lastPlay { Text("Last play: \(play)").foregroundStyle(.secondary).frame(maxWidth: 520) }
                    Text([game.venue, game.broadcast].compactMap { $0 }.joined(separator: "  ·  ")).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        } else { Text("No game to show yet.").foregroundStyle(.secondary) }
    }
}

// MARK: - Settings window

/// Choose your schools on the dial of every mlb team; they become the rotating cards on the zone.
final class BaseballSettingsController {
    static let shared = BaseballSettingsController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "MLB Baseball Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 940, height: 680)
            w.contentView = NSHostingView(rootView: BaseballSettingsView())
            w.center()
            window = w
        }
        BaseballStore.shared.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct BaseballSettingsView: View {
    @ObservedObject var store = BaseballStore.shared
    @StateObject private var picker: PickerState
    init(picker: PickerState = PickerState()) { _picker = StateObject(wrappedValue: picker) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                PickerToolbar(store: store, state: picker).padding(.horizontal, 12).padding(.top, 10)
                GeometryReader { proxy in SportsDial(store: store, state: picker, geo: FGeo(placement: "full", size: proxy.size)) }
            }.frame(minWidth: 620)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your teams").font(.title3.weight(.semibold))
                    Text("Click a team on the dial to add or remove it; double-click for its details. Your teams rotate as cards on the zone.").font(.callout).foregroundStyle(.secondary)
                    if store.favorites.isEmpty { Text("No teams picked yet.").foregroundStyle(.secondary) }
                    ForEach(Array(store.favorites.enumerated()), id: \.element) { i, abbr in
                        HStack(spacing: 8) {
                            TeamLogo(abbr: abbr, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) { RankTag(rank: store.rank(of: abbr), size: 10); Text(store.team(abbr)?.name ?? abbr) }
                                Text(store.team(abbr)?.conference ?? "").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                            Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == store.favorites.count - 1)
                            Button { store.favorites.remove(at: i) } label: { Image(systemName: "xmark") }
                        }.buttonStyle(.borderless)
                    }
                    if !store.favorites.isEmpty { Button("Remove all") { store.favorites = [] } }
                    Divider()
                    Text("Options").font(.headline)
                    Toggle("Show team logos", isOn: $store.showLogos)
                    Text("Logos are loaded from the internet while the zone runs. Off shows a badge in the team's colors instead.").font(.caption).foregroundStyle(.secondary)
                    Picker("Rotate cards every", selection: $store.rotateSeconds) {
                        Text("5 seconds").tag(5.0); Text("8 seconds").tag(8.0); Text("12 seconds").tag(12.0); Text("20 seconds").tag(20.0); Text("Don't rotate").tag(0.0)
                    }
                    Toggle("Small game dial beside the corner icon", isOn: $store.chipEnabled)
                    Text("While one of your teams is playing (or about to), a thin dial by the zone's icon shows how far into the game it is, who leads, and when a runner is in scoring position.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Score alerts").font(.headline)
                    Picker("Show it", selection: $store.alertStyle) {
                        Text("In the zone (it opens bigger)").tag("zone"); Text("In a separate window").tag("window"); Text("Both").tag("both")
                    }.disabled(store.alertMode == "off")
                    if !BaseballStore.appCanOpenZones && store.alertStyle != "window" {
                        Text("Opening the zone itself needs Zones 0.14 or newer. Until then the separate window is used.").font(.caption).foregroundStyle(.orange)
                    }
                    Picker("When a team scores", selection: $store.alertMode) {
                        Text("Don't show").tag("off"); Text("Home runs only").tag("hr"); Text("Every run").tag("all")
                    }
                    Toggle("Also for teams I don't follow", isOn: $store.alertOthers).disabled(store.alertMode == "off")
                    Picker("Keep it up for", selection: $store.alertSeconds) {
                        Text("6 seconds").tag(6.0); Text("10 seconds").tag(10.0); Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0)
                    }.disabled(store.alertMode == "off")
                    Button("Preview alert") {
                        let a = store.favorites.first ?? store.teams.first?.abbr ?? "NYY"
                        var g = Game(id: "preview", date: Date(), state: .live, away: store.teams.first { $0.abbr != a }?.abbr ?? "BOS", home: a)
                        g.homeScore = 4; g.awayScore = 3; g.period = 7; g.half = "bottom"; g.outs = 1; g.lastPlay = "Home run to left field, 2 runs score."
                        store.showAlert(ScoreAlertInfo(kind: "HOME RUN", team: a, points: 2, game: g))
                    }
                    Text("In the zone, it opens bigger on the card with a banner, then settles back. Home runs are recognized from the play description in the feed. The separate window is a card beside the zone's icon. Scores are noticed within about 20 seconds.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Unofficial. Not affiliated with Major League Baseball or any team. Schedules, scores, standings and rankings come from ESPN's public ESPN's public MLB feed.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 340)
        }
    }
    private func move(_ i: Int, _ d: Int) { store.favorites.swapAt(i, i + d) }
}
