import AppKit
import SwiftUI

// MARK: - Details window (double-click or click a card)

/// Season scores, conference standings, the AP Top 25, school stats and the live game, in a window that stays open and
/// remembers its size and place.
final class CollegeDetailsController {
    static let shared = CollegeDetailsController()
    private var window: NSWindow?
    let selection = CollegeSelection()

    func show(team: String, game: Game?) {
        selection.team = team
        selection.gameID = game?.id
        selection.tab = game?.state == .live ? .live : .scores
        CollegeStore.shared.loadSchedule(team)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "College Football"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.minSize = NSSize(width: 740, height: 540)
            w.contentView = NSHostingView(rootView: DetailsView(selection: selection))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("CollegeFootballDetailsWindow") { w.center() }
            w.setFrameAutosaveName("CollegeFootballDetailsWindow")
            window = w
        }
        CollegeStore.shared.refreshBoard()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum CollegeTab: String, CaseIterable, Identifiable { case scores = "Season", standings = "Standings", top25 = "Top 25", stats = "Team stats", live = "Live game"; var id: String { rawValue } }

final class CollegeSelection: ObservableObject {
    @Published var team = ""
    @Published var gameID: String?
    @Published var tab: CollegeTab = .scores
}

struct DetailsView: View {
    @ObservedObject var selection: CollegeSelection
    @ObservedObject var store = CollegeStore.shared
    var body: some View {
        let team = store.team(selection.team)
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TeamLogo(abbr: selection.team, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) { RankTag(rank: store.rank(of: selection.team), size: 16); Text(team?.name ?? selection.team).font(.title2.weight(.semibold)) }
                    Text("\(team?.conference ?? "")  ·  \(store.standing(for: selection.team).map { "\($0.overall) (\($0.conf) in conference)" } ?? "")").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !store.favorites.isEmpty {
                        Section("My schools") { ForEach(store.favorites, id: \.self) { a in Button(store.team(a)?.school ?? a) { pick(a) } } }
                    }
                    ForEach(store.conferences, id: \.self) { c in Menu(c) { ForEach(store.teams(in: c)) { t in Button(t.school) { pick(t.abbr) } } } }
                } label: { Label("Change school", systemImage: "arrow.left.arrow.right") }.fixedSize()
                Button { store.refreshBoard(); store.loadSchedule(selection.team) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh now")
            }
            Picker("", selection: $selection.tab) { ForEach(CollegeTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch selection.tab {
                case .scores: SeasonTab(team: selection.team, selection: selection)
                case .standings: StandingsTab(selected: selection.team, selection: selection)
                case .top25: Top25Tab(selection: selection)
                case .stats: StatsTab(team: selection.team)
                case .live: LiveTab(team: selection.team, gameID: selection.gameID)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(store.offline ? "Offline: showing saved data." : (store.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                Spacer()
                Text("Unofficial. Not affiliated with the NCAA or any school. Data: ESPN's public college football feed.")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func pick(_ abbr: String) { selection.team = abbr; store.loadSchedule(abbr); selection.gameID = store.currentGame(for: abbr)?.id }
}

extension CollegeSelection {
    /// Switches the whole window to another school, on its season page.
    func open(_ abbr: String) {
        team = abbr
        CollegeStore.shared.loadSchedule(abbr)
        gameID = CollegeStore.shared.currentGame(for: abbr)?.id
        tab = .scores
    }
}

// MARK: Season (every game of a school)

private struct SeasonTab: View {
    let team: String
    @ObservedObject var selection: CollegeSelection
    @ObservedObject var store = CollegeStore.shared
    var body: some View {
        let games = store.games(for: team)
        if games.isEmpty { Text("Loading the schedule…").foregroundStyle(.secondary) }
        else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(games) { g in
                        let opp = g.opponent(of: team), home = g.home == team
                        HStack(spacing: 12) {
                            Text("Wk \(g.week)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
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
                if g.overtime { Text("OT").font(.caption).foregroundStyle(.orange) }
            }.frame(width: 190, alignment: .trailing)
        }
    }
}

// MARK: Conference standings

private struct StandingsTab: View {
    let selected: String
    @ObservedObject var selection: CollegeSelection
    @State private var conference: String?
    @ObservedObject var store = CollegeStore.shared
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
                        ForEach(["Conf", "Overall", "PF", "PA", "Diff", "Strk"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(width: 52) }
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
                            Text(r.conf).frame(width: 52); Text(r.overall).frame(width: 52); Text("\(r.pf)").frame(width: 52); Text("\(r.pa)").frame(width: 52)
                            Text(r.diff > 0 ? "+\(r.diff)" : "\(r.diff)").foregroundStyle(r.diff > 0 ? Color.green : r.diff < 0 ? Color.red : .secondary).frame(width: 52)
                            Text(r.streak).frame(width: 52)
                        }.font(.callout.monospacedDigit()).padding(.vertical, 3).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(r.team == selected ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { selection.open(r.team) }
                        .help("Double-click for this school's details")
                    }
                }
            }
        }
    }
}

// MARK: AP Top 25

private struct Top25Tab: View {
    @ObservedObject var selection: CollegeSelection
    @ObservedObject var store = CollegeStore.shared
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
                        .help("Double-click for this school's details")
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
    @ObservedObject var store = CollegeStore.shared
    var body: some View {
        if let s = store.standing(for: team) {
            let results = store.games(for: team).filter { $0.state == .post }
            let g = max(1, results.count)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        tile("Record", s.overall, "\(s.conf) in conference"); tile("Streak", s.streak)
                        tile("Points for", "\(s.pf)", String(format: "%.1f per game", Double(s.pf) / Double(g)))
                        tile("Points against", "\(s.pa)", String(format: "%.1f per game", Double(s.pa) / Double(g)))
                        tile("Point differential", s.diff > 0 ? "+\(s.diff)" : "\(s.diff)")
                        tile("Home", record(results.filter { $0.home == team })); tile("Away", record(results.filter { $0.away == team }))
                        tile("AP rank", store.rank(of: team).map { "#\($0)" } ?? "Unranked")
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
    @ObservedObject var store = CollegeStore.shared
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

/// Choose your schools on the dial of every FBS school; they become the rotating cards on the zone.
final class CollegeSettingsController {
    static let shared = CollegeSettingsController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "College Football Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 940, height: 680)
            w.contentView = NSHostingView(rootView: CollegeSettingsView())
            w.center()
            window = w
        }
        CollegeStore.shared.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct CollegeSettingsView: View {
    @ObservedObject var store = CollegeStore.shared
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
                    Text("Your schools").font(.title3.weight(.semibold))
                    Text("Click a school on the dial to add or remove it; double-click for its details. Your schools rotate as cards on the zone.").font(.callout).foregroundStyle(.secondary)
                    if store.favorites.isEmpty { Text("No schools picked yet.").foregroundStyle(.secondary) }
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
                    Toggle("Show school logos", isOn: $store.showLogos)
                    Text("Logos are loaded from the internet while the zone runs. Off shows a badge in the school's colors instead.").font(.caption).foregroundStyle(.secondary)
                    Picker("Rotate cards every", selection: $store.rotateSeconds) {
                        Text("5 seconds").tag(5.0); Text("8 seconds").tag(8.0); Text("12 seconds").tag(12.0); Text("20 seconds").tag(20.0); Text("Don't rotate").tag(0.0)
                    }
                    Toggle("Small game dial beside the corner icon", isOn: $store.chipEnabled)
                    Text("While one of your schools is playing (or about to), a thin dial by the zone's icon shows how far into the game it is, who leads, and the red zone.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Score alerts").font(.headline)
                    Picker("Show it", selection: $store.alertStyle) {
                        Text("In the zone (it opens bigger)").tag("zone"); Text("In a separate window").tag("window"); Text("Both").tag("both")
                    }.disabled(store.alertMode == "off")
                    if !CollegeStore.appCanOpenZones && store.alertStyle != "window" {
                        Text("Opening the zone itself needs Zones 0.14 or newer. Until then the separate window is used.").font(.caption).foregroundStyle(.orange)
                    }
                    Picker("When a team scores", selection: $store.alertMode) {
                        Text("Don't show").tag("off"); Text("Touchdowns only").tag("td"); Text("Every scoring play").tag("all")
                    }
                    Toggle("Also for schools I don't follow", isOn: $store.alertOthers).disabled(store.alertMode == "off")
                    Picker("Keep it up for", selection: $store.alertSeconds) {
                        Text("6 seconds").tag(6.0); Text("10 seconds").tag(10.0); Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0)
                    }.disabled(store.alertMode == "off")
                    Button("Preview alert") {
                        let a = store.favorites.first ?? store.teams.first?.abbr ?? "ALA"
                        var g = Game(id: "preview", week: store.currentWeek, date: Date(), state: .live, away: store.teams.first { $0.abbr != a }?.abbr ?? "UGA", home: a)
                        g.homeScore = 21; g.awayScore = 17; g.period = 3; g.clock = "8:42"; g.lastPlay = "Touchdown, 32-yard pass for the score."
                        store.showAlert(ScoreAlertInfo(kind: "TOUCHDOWN", team: a, points: 7, game: g))
                    }
                    Text("In the zone, it opens bigger on the school's card with a banner, then settles back. The separate window is a card beside the zone's icon. Scores are noticed within about 20 seconds.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Unofficial. Not affiliated with the NCAA or any school. Schedules, scores, standings and rankings come from ESPN's public college football feed.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 340)
        }
    }
    private func move(_ i: Int, _ d: Int) { store.favorites.swapAt(i, i + d) }
}
