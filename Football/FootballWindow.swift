import AppKit
import SwiftUI

// MARK: - Details window (click a card)

/// Season scores, standings, team stats and the live game, in a window that stays open and remembers its size and place.
final class FootballDetailsController {
    static let shared = FootballDetailsController()
    private var window: NSWindow?
    let selection = DetailsSelection()

    func show(team: String, game: Game?) {
        selection.team = team
        selection.gameID = game?.id
        selection.tab = game?.state == .live ? .live : .scores
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "NFL Football"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.minSize = NSSize(width: 720, height: 520)
            w.contentView = NSHostingView(rootView: DetailsView(selection: selection))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("FootballDetailsWindow") { w.center() }
            w.setFrameAutosaveName("FootballDetailsWindow")
            window = w
        }
        FootballStore.shared.refreshBoard()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum DetailsTab: String, CaseIterable, Identifiable { case scores = "Scores", standings = "Standings", stats = "Team stats", live = "Live game"; var id: String { rawValue } }

extension DetailsSelection {
    /// Switches the whole window to another team, on its scores page.
    func open(_ abbr: String) {
        team = abbr
        gameID = FootballStore.shared.currentGame(for: abbr)?.id
        tab = .scores
    }
}

final class DetailsSelection: ObservableObject {
    @Published var team = ""
    @Published var gameID: String?
    @Published var tab: DetailsTab = .scores
}

private struct DetailsView: View {
    @ObservedObject var selection: DetailsSelection
    @ObservedObject var store = FootballStore.shared
    var body: some View {
        let team = store.team(selection.team)
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TeamLogo(abbr: selection.team, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team?.name ?? selection.team).font(.title2.weight(.semibold))
                    Text("\(team?.division ?? "")  ·  \(store.standings.first { $0.team.abbr == selection.team }?.record ?? "0-0")").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !store.favorites.isEmpty {
                        Section("My teams") { ForEach(store.favorites, id: \.self) { a in Button(store.team(a)?.name ?? a) { pick(a) } } }
                    }
                    ForEach(FootballStore.divisions, id: \.self) { d in
                        Menu(d) { ForEach(store.teams.filter { $0.division == d }) { t in Button(t.name) { pick(t.abbr) } } }
                    }
                } label: { Label("Change team", systemImage: "arrow.left.arrow.right") }.fixedSize()
                Button { store.refreshBoard() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh now")
            }
            Picker("", selection: $selection.tab) { ForEach(DetailsTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch selection.tab {
                case .scores: ScoresTab(team: selection.team, selection: selection)
                case .standings: StandingsTab(selected: selection.team, selection: selection)
                case .stats: StatsTab(team: selection.team)
                case .live: LiveTab(team: selection.team, gameID: selection.gameID)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(store.offline ? "Offline: showing saved data." : (store.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                Spacer()
                Text("Unofficial. Not affiliated with the NFL or any team. Data: nflverse (open data) and ESPN's public scoreboard feed.")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func pick(_ abbr: String) { selection.team = abbr; selection.gameID = store.currentGame(for: abbr)?.id }
}

// MARK: Scores (the whole season for a team)

private struct ScoresTab: View {
    let team: String
    @ObservedObject var selection: DetailsSelection
    @ObservedObject var store = FootballStore.shared
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
                            Text(store.team(opp)?.name ?? opp).frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: Standings

private struct StandingsTab: View {
    let selected: String
    @ObservedObject var selection: DetailsSelection
    @ObservedObject var store = FootballStore.shared
    var body: some View {
        let standings = store.standings
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                conference("AFC", standings)
                conference("NFC", standings)
            }
        }
    }
    private func conference(_ name: String, _ all: [TeamStanding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.headline)
            ForEach(FootballStore.divisions.filter { $0.hasPrefix(name) }, id: \.self) { d in
                let rows = all.filter { $0.team.division == d }.sorted { ($0.pct, $0.diff) > ($1.pct, $1.diff) }
                VStack(spacing: 2) {
                    HStack {
                        Text(d.dropFirst(4)).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(["W-L", "PF", "PA", "Diff", "Strk"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(width: 40) }
                    }
                    ForEach(rows) { s in
                        HStack {
                            TeamLogo(abbr: s.team.abbr, size: 22)
                            HStack(spacing: 4) {
                                Text(s.team.nick).lineLimit(1).fontWeight(store.favorites.contains(s.team.abbr) || s.team.abbr == selected ? .bold : .regular)
                                if store.favorites.contains(s.team.abbr) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(s.record).frame(width: 40); Text("\(s.pf)").frame(width: 40); Text("\(s.pa)").frame(width: 40)
                            Text(s.diff > 0 ? "+\(s.diff)" : "\(s.diff)").foregroundStyle(s.diff > 0 ? Color.green : s.diff < 0 ? Color.red : .secondary).frame(width: 40)
                            Text(s.streak).frame(width: 40)
                        }.font(.callout.monospacedDigit()).padding(.vertical, 2).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(s.team.abbr == selected ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { selection.open(s.team.abbr) }
                        .help("Double-click for this team's details")
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: Team stats

private struct StatsTab: View {
    let team: String
    @ObservedObject var store = FootballStore.shared
    var body: some View {
        if let s = store.standings.first(where: { $0.team.abbr == team }) {
            let g = max(1, s.games)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        tile("Record", s.record); tile("Streak", s.streak)
                        tile("Points for", "\(s.pf)", "\(String(format: "%.1f", Double(s.pf) / Double(g))) per game")
                        tile("Points against", "\(s.pa)", "\(String(format: "%.1f", Double(s.pa) / Double(g))) per game")
                        tile("Point differential", s.diff > 0 ? "+\(s.diff)" : "\(s.diff)")
                        tile("Home", "\(s.homeW)-\(s.homeL)"); tile("Away", "\(s.awayW)-\(s.awayL)")
                        tile("Division", "\(s.divW)-\(s.divL)")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last games").font(.headline)
                        HStack(spacing: 8) {
                            ForEach(Array(s.last.suffix(5).enumerated()), id: \.offset) { _, won in
                                Text(won ? "W" : "L").font(.headline).frame(width: 34, height: 34).background(Circle().fill(won ? Color.green.opacity(0.7) : Color.red.opacity(0.7))).foregroundStyle(.white)
                            }
                            if s.last.isEmpty { Text("No games played yet.").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        } else { Text("Loading…").foregroundStyle(.secondary) }
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
    @ObservedObject var store = FootballStore.shared
    var body: some View {
        let game = store.board(week: store.currentWeek).first { $0.id == gameID } ?? store.season.compactMap { s in store.board(week: s.week).first { $0.id == gameID } }.first ?? store.currentGame(for: team)
        if let game {
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

/// Choose your favorite teams on the dial of all 32; they become the rotating cards on the zone.
final class FootballSettingsController {
    static let shared = FootballSettingsController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "NFL Football Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 940, height: 680)
            w.contentView = NSHostingView(rootView: FootballSettingsView())
            w.center()
            window = w
        }
        FootballStore.shared.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct FootballSettingsView: View {
    @ObservedObject var store = FootballStore.shared
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
                    Text("Click a team on the dial to add or remove it. Your teams rotate as cards on the zone.").font(.callout).foregroundStyle(.secondary)
                    if store.favorites.isEmpty { Text("No teams picked yet.").foregroundStyle(.secondary) }
                    ForEach(Array(store.favorites.enumerated()), id: \.element) { i, abbr in
                        HStack(spacing: 8) {
                            TeamLogo(abbr: abbr, size: 26)
                            Text(store.team(abbr)?.name ?? abbr).frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("While one of your teams is playing (or about to), a thin dial by the zone's icon shows how far into the game it is.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Score pop-up").font(.headline)
                    Picker("Show it", selection: $store.alertStyle) {
                        Text("In the zone (it opens bigger)").tag("zone"); Text("In a separate window").tag("window"); Text("Both").tag("both")
                    }.disabled(store.alertMode == "off")
                    if !FootballStore.appCanOpenZones && store.alertStyle != "window" {
                        Text("Opening the zone itself needs a newer Zones app. Until then the separate window is used.").font(.caption).foregroundStyle(.orange)
                    }
                    Picker("When a team scores", selection: $store.alertMode) {
                        Text("Don't show").tag("off"); Text("Touchdowns only").tag("td"); Text("Every scoring play").tag("all")
                    }
                    Toggle("Also for teams I don't follow", isOn: $store.alertOthers).disabled(store.alertMode == "off")
                    Picker("Keep it up for", selection: $store.alertSeconds) {
                        Text("6 seconds").tag(6.0); Text("10 seconds").tag(10.0); Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0)
                    }.disabled(store.alertMode == "off")
                    HStack {
                        Button("Preview pop-up") {
                            var g = Game(id: "preview", week: store.currentWeek, date: Date(), state: .live, away: "GB", home: "NYJ")
                            g.awayScore = 14; g.homeScore = 10; g.period = 3; g.clock = "8:42"; g.lastPlay = "J.Love pass deep right to J.Reed for 32 yards, TOUCHDOWN."
                            store.showAlert(ScoreAlertInfo(kind: "TOUCHDOWN", team: "GB", points: 7, game: g))
                        }
                    }
                    Text("In the zone, it opens bigger on the team's card with a banner, the way Media opens for a new song, then settles back. The separate window is a card beside the zone's icon. Scores are noticed within about 20 seconds.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Unofficial. Not affiliated with the NFL or any team. Schedules and past scores are open data from nflverse; live scores come from ESPN's public scoreboard feed.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 340)
        }
    }
    private func move(_ i: Int, _ d: Int) { store.favorites.swapAt(i, i + d) }
}
