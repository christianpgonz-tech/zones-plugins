import AppKit
import SwiftUI

// MARK: - Details window (click a card)

/// Season results, league tables, club stats and the match itself, in a window that stays open and remembers its size and place.
final class SoccerDetailsController {
    static let shared = SoccerDetailsController()
    private var window: NSWindow?
    let selection = SoccerSelection()

    func show(team: String, match: Match?) {
        selection.team = team
        selection.matchID = match?.id
        selection.tab = match?.state == .live ? .match : .results
        SoccerStore.shared.loadSchedule(team)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Soccer"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.minSize = NSSize(width: 740, height: 540)
            w.contentView = NSHostingView(rootView: DetailsView(selection: selection))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("SoccerDetailsWindow") { w.center() }
            w.setFrameAutosaveName("SoccerDetailsWindow")
            window = w
        }
        SoccerStore.shared.refreshBoards()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SoccerTab: String, CaseIterable, Identifiable { case results = "Results", table = "Table", stats = "Club stats", match = "Match"; var id: String { rawValue } }

final class SoccerSelection: ObservableObject {
    @Published var team = ""
    @Published var matchID: String?
    @Published var tab: SoccerTab = .results
}

struct DetailsView: View {
    @ObservedObject var selection: SoccerSelection
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let team = store.team(selection.team)
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TeamLogo(key: selection.team, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team?.name ?? "Club").font(.title2.weight(.semibold))
                    Text("\(League.named(team?.league ?? "").name)\(store.standing(for: selection.team).map { "  ·  #\($0.rank)  ·  \($0.pts) pts" } ?? "")").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !store.favorites.isEmpty {
                        Section("My clubs") { ForEach(store.favorites, id: \.self) { k in Button(store.team(k)?.name ?? k) { pick(k) } } }
                    }
                    ForEach(League.all) { l in Menu(l.name) { ForEach(store.teams(in: l.code)) { t in Button(t.name) { pick(t.key) } } } }
                } label: { Label("Change club", systemImage: "arrow.left.arrow.right") }.fixedSize()
                Button { store.refreshBoards(); store.loadSchedule(selection.team) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh now")
            }
            Picker("", selection: $selection.tab) { ForEach(SoccerTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch selection.tab {
                case .results: ResultsTab(team: selection.team, selection: selection)
                case .table: TableTab(selected: selection.team, league: team?.league ?? "eng.1", selection: selection)
                case .stats: StatsTab(team: selection.team)
                case .match: MatchTab(team: selection.team, matchID: selection.matchID)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(store.offline ? "Offline: showing saved data." : (store.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                Spacer()
                Text("Unofficial. Not affiliated with any league or club. Data: ESPN's public soccer feed.")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func pick(_ key: String) {
        selection.team = key; store.loadSchedule(key); selection.matchID = store.currentMatch(for: key)?.id
    }
}

// MARK: Results (season results and fixtures)

private struct ResultsTab: View {
    let team: String
    @ObservedObject var selection: SoccerSelection
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let matches = (store.schedules[team] ?? []).map { store.fresh($0) }
        if matches.isEmpty { Text("Loading the season…").foregroundStyle(.secondary) }
        else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(matches) { m in
                        let opp = m.opponent(of: team), home = m.home == team
                        HStack(spacing: 12) {
                            Text(m.date.formatted(.dateTime.month(.abbreviated).day())).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                            Text(home ? "vs" : "@").foregroundStyle(.secondary).frame(width: 20)
                            TeamLogo(key: opp, size: 28)
                            Text(store.team(opp)?.name ?? "Club").frame(maxWidth: .infinity, alignment: .leading)
                            resultView(m)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 9).fill(m.state == .live ? Color.red.opacity(0.12) : Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                        .onTapGesture { selection.matchID = m.id; selection.tab = .match }
                    }
                }
            }
        }
    }
    @ViewBuilder private func resultView(_ m: Match) -> some View {
        switch m.state {
        case .pre: Text(Match.kickoff.string(from: m.date)).foregroundStyle(.secondary).frame(width: 190, alignment: .trailing)
        case .live: Text("LIVE  \(m.statusLine)  \(m.score(of: team))–\(m.score(of: m.opponent(of: team)))").foregroundStyle(.red).fontWeight(.semibold).frame(width: 190, alignment: .trailing)
        case .post:
            let mine = m.score(of: team), theirs = m.score(of: m.opponent(of: team))
            HStack(spacing: 6) {
                Text(mine > theirs ? "W" : mine < theirs ? "L" : "D").fontWeight(.bold).foregroundStyle(mine > theirs ? Color.green : mine < theirs ? Color.red : .secondary)
                Text("\(mine)–\(theirs)").monospacedDigit()
            }.frame(width: 190, alignment: .trailing)
        }
    }
}

// MARK: League table

struct TableTab: View {
    let selected: String
    @State var league: String
    @ObservedObject var selection: SoccerSelection
    @ObservedObject var store = SoccerStore.shared
    init(selected: String, league: String, selection: SoccerSelection) { self.selected = selected; _league = State(initialValue: league); self.selection = selection }
    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $league) { ForEach(League.all) { Text($0.name).tag($0.code) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let groups = store.standings[league] ?? []
                    if groups.isEmpty { Text("Loading the table…").foregroundStyle(.secondary) }
                    ForEach(groups) { g in
                        VStack(spacing: 2) {
                            HStack {
                                Text(groups.count > 1 ? g.name : "").font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                ForEach(["P", "W", "D", "L", "GF", "GA", "GD", "Pts"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(width: 34) }
                            }
                            ForEach(g.rows) { r in
                                HStack {
                                    Text("\(r.rank)").frame(width: 24).foregroundStyle(.secondary)
                                    TeamLogo(key: r.teamKey, size: 22)
                                    HStack(spacing: 4) {
                                        Text(store.team(r.teamKey)?.short ?? "Club").lineLimit(1).fontWeight(store.favorites.contains(r.teamKey) || r.teamKey == selected ? .bold : .regular)
                                        if store.favorites.contains(r.teamKey) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04)) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(r.played)").frame(width: 34); Text("\(r.w)").frame(width: 34); Text("\(r.d)").frame(width: 34); Text("\(r.l)").frame(width: 34)
                                    Text("\(r.gf)").frame(width: 34); Text("\(r.ga)").frame(width: 34)
                                    Text(r.gd > 0 ? "+\(r.gd)" : "\(r.gd)").foregroundStyle(r.gd > 0 ? Color.green : r.gd < 0 ? Color.red : .secondary).frame(width: 34)
                                    Text("\(r.pts)").fontWeight(.bold).frame(width: 34)
                                }.font(.callout.monospacedDigit()).padding(.vertical, 2).padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(r.teamKey == selected ? Color.accentColor.opacity(0.18) : .clear))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { openClub(r.teamKey) }
                                .help("Double-click for this club's details")
                            }
                        }
                    }
                }
            }
        }
    }
}

extension TableTab {
    /// Switches the whole window to the club that was double-clicked, on its Results page.
    fileprivate func openClub(_ key: String) {
        selection.team = key
        SoccerStore.shared.loadSchedule(key)
        selection.matchID = SoccerStore.shared.currentMatch(for: key)?.id
        selection.tab = .results
    }
}

// MARK: Club stats

private struct StatsTab: View {
    let team: String
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let results = (store.schedules[team] ?? []).filter { $0.state == .post }
        let row = store.standing(for: team)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    tile("Position", row.map { "#\($0.rank)" } ?? "—", row.map { "\($0.pts) points" })
                    tile("Record", row.map { "\($0.w)-\($0.d)-\($0.l)" } ?? "—", "wins-draws-losses")
                    let gp = max(1, row?.played ?? 1)
                    tile("Goals for", "\(row?.gf ?? 0)", String(format: "%.1f per match", Double(row?.gf ?? 0) / Double(gp)))
                    tile("Goals against", "\(row?.ga ?? 0)", String(format: "%.1f per match", Double(row?.ga ?? 0) / Double(gp)))
                    tile("Goal difference", row.map { $0.gd > 0 ? "+\($0.gd)" : "\($0.gd)" } ?? "—")
                    tile("Home", record(results.filter { $0.home == team }), "wins-draws-losses")
                    tile("Away", record(results.filter { $0.away == team }), "wins-draws-losses")
                    tile("Clean sheets", "\(results.filter { $0.score(of: $0.opponent(of: team)) == 0 }.count)")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Form (last five)").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(Array(results.suffix(5).enumerated()), id: \.offset) { _, m in
                            let mine = m.score(of: team), theirs = m.score(of: m.opponent(of: team))
                            Text(mine > theirs ? "W" : mine < theirs ? "L" : "D").font(.headline).frame(width: 34, height: 34)
                                .background(Circle().fill(mine > theirs ? Color.green.opacity(0.7) : mine < theirs ? Color.red.opacity(0.7) : Color.gray.opacity(0.6))).foregroundStyle(.white)
                        }
                        if results.isEmpty { Text("No matches played yet.").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private func record(_ list: [Match]) -> String {
        var w = 0, d = 0, l = 0
        for m in list { let a = m.score(of: team), b = m.score(of: m.opponent(of: team)); if a > b { w += 1 } else if a < b { l += 1 } else { d += 1 } }
        return "\(w)-\(d)-\(l)"
    }
    private func tile(_ title: String, _ value: String, _ note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold).monospacedDigit())
            Text(note ?? " ").font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: The match

private struct MatchTab: View {
    let team: String
    let matchID: String?
    @ObservedObject var store = SoccerStore.shared
    var body: some View {
        let found = store.allBoard.first { $0.id == matchID } ?? (store.schedules[team] ?? []).first { $0.id == matchID } ?? store.currentMatch(for: team)
        if let m = found {
            ScrollView {
                VStack(spacing: 14) {
                    MatchCard(match: m, focus: team).frame(width: 320).scaleEffect(1.5).frame(width: 480, height: 400)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Goals and cards").font(.headline)
                        if m.events.isEmpty { Text(m.state == .pre ? "The match hasn't started." : "No goals or cards.").foregroundStyle(.secondary) }
                        ForEach(m.events.sorted { $0.seconds < $1.seconds }) { e in
                            HStack(spacing: 8) {
                                Text(e.minute).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                                switch e.kind {
                                case .yellow: RoundedRectangle(cornerRadius: 2).fill(Color(red: 1, green: 0.84, blue: 0.1)).frame(width: 10, height: 14)
                                case .red: RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.95, green: 0.2, blue: 0.2)).frame(width: 10, height: 14)
                                default: Image(systemName: "soccerball")
                                }
                                Text(e.player).fontWeight(e.isGoal ? .semibold : .regular)
                                Text(e.kind == .penaltyGoal ? "(penalty)" : e.kind == .ownGoal ? "(own goal)" : "").foregroundStyle(.secondary)
                                Spacer()
                                Text(store.team(e.teamID == m.homeID ? m.home : m.away)?.short ?? "").foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: 520, alignment: .leading)
                    Text([m.venue, m.broadcast].compactMap { $0 }.joined(separator: "  ·  ")).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        } else { Text("No match to show yet.").foregroundStyle(.secondary) }
    }
}

// MARK: - Settings window

/// Choose your clubs on the dial of all 70; they become the rotating cards on the zone.
final class SoccerSettingsController {
    static let shared = SoccerSettingsController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Soccer Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 940, height: 680)
            w.contentView = NSHostingView(rootView: SoccerSettingsView())
            w.center()
            window = w
        }
        SoccerStore.shared.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SoccerSettingsView: View {
    @ObservedObject var store = SoccerStore.shared
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
                    Text("Your clubs").font(.title3.weight(.semibold))
                    Text("Click a club on the dial to add or remove it. Your clubs rotate as cards on the zone.").font(.callout).foregroundStyle(.secondary)
                    if store.favorites.isEmpty { Text("No clubs picked yet.").foregroundStyle(.secondary) }
                    ForEach(Array(store.favorites.enumerated()), id: \.element) { i, key in
                        HStack(spacing: 8) {
                            TeamLogo(key: key, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(store.team(key)?.name ?? key)
                                Text(League.named(store.team(key)?.league ?? "").short).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                            Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == store.favorites.count - 1)
                            Button { store.favorites.remove(at: i) } label: { Image(systemName: "xmark") }
                        }.buttonStyle(.borderless)
                    }
                    if !store.favorites.isEmpty { Button("Remove all") { store.favorites = [] } }
                    Divider()
                    Text("Options").font(.headline)
                    Toggle("Show club logos", isOn: $store.showLogos)
                    Text("Logos are loaded from the internet while the zone runs. Off shows a badge in the club's colors instead.").font(.caption).foregroundStyle(.secondary)
                    Picker("Rotate cards every", selection: $store.rotateSeconds) {
                        Text("5 seconds").tag(5.0); Text("8 seconds").tag(8.0); Text("12 seconds").tag(12.0); Text("20 seconds").tag(20.0); Text("Don't rotate").tag(0.0)
                    }
                    Toggle("Small match dial beside the corner icon", isOn: $store.chipEnabled)
                    Text("While one of your clubs is playing (or about to), a thin dial by the zone's icon shows the minute, who leads, and goals.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Goal alerts").font(.headline)
                    Picker("Show it", selection: $store.alertStyle) {
                        Text("In the zone (it opens bigger)").tag("zone"); Text("In a separate window").tag("window"); Text("Both").tag("both")
                    }.disabled(store.alertMode == "off")
                    if !SoccerStore.appCanOpenZones && store.alertStyle != "window" {
                        Text("Opening the zone itself needs Zones 0.14 or newer. Until then the separate window is used.").font(.caption).foregroundStyle(.orange)
                    }
                    Picker("Alert for", selection: $store.alertMode) {
                        Text("Nothing").tag("off"); Text("Goals").tag("goals"); Text("Goals and red cards").tag("goalscards")
                    }
                    Toggle("Also for clubs I don't follow", isOn: $store.alertOthers).disabled(store.alertMode == "off")
                    Picker("Keep it up for", selection: $store.alertSeconds) {
                        Text("6 seconds").tag(6.0); Text("10 seconds").tag(10.0); Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0)
                    }.disabled(store.alertMode == "off")
                    Button("Preview alert") {
                        let a = store.favorites.first ?? store.teams.first?.key ?? "eng.1:382"
                        var m = Match(id: "preview", league: String(a.split(separator: ":").first ?? "eng.1"), date: Date(), state: .live, home: a, away: store.teams.first { $0.key != a }?.key ?? "eng.1:349")
                        m.homeScore = 2; m.awayScore = 1; m.period = 2; m.clock = "67'"; m.clockSeconds = 4020
                        m.homeID = a.split(separator: ":").last.map(String.init) ?? ""
                        m.events = [MatchEvent(id: 1, kind: .goal, minute: "67'", seconds: 4020, teamID: m.homeID, player: "E. Haaland")]
                        store.showAlert(ScoreAlertInfo(kind: "GOAL", team: a, detail: "E. Haaland 67'", match: m))
                    }
                    Text("In the zone, it opens bigger on the club's card with a banner, then settles back. The separate window is a card beside the zone's icon. Goals are noticed within about 20 seconds.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Unofficial. Not affiliated with any league or club. Fixtures, scores and tables come from ESPN's public soccer feed.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 340)
        }
    }
    private func move(_ i: Int, _ d: Int) { store.favorites.swapAt(i, i + d) }
}
