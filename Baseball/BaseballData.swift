enum BaseballSport {
    static let regulation = 9
    static let periodSeconds = 0.0
    static let periodNames = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    static let extraLabel = "X"
}

import AppKit
import SwiftUI

// MARK: - Models

struct Team: Identifiable, Hashable {
    let abbr: String
    let espnID: String
    let school: String          // "Alabama"
    let name: String            // "Alabama Crimson Tide"
    let nick: String            // "Crimson Tide"
    let conference: String      // "SEC" (empty for opponents outside the FBS list)
    let colorHex: String
    let logoURL: URL?
    var id: String { abbr }
    var color: Color { Color(hex: colorHex) }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        if s.count != 6 { s = "444444" }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

struct Game: Identifiable, Hashable {
    enum State { case pre, live, post }
    let id: String
    var date: Date
    var state: State
    var period = 0              // the inning
    var half = ""               // while live: "top", "bottom", "mid" (between halves) or "end" (end of the inning)
    var statusText = ""
    var away: String            // team abbreviations
    var home: String
    var awayScore = 0
    var homeScore = 0
    var awayHits = 0, homeHits = 0, awayErrors = 0, homeErrors = 0
    var awayRecord: String?
    var homeRecord: String?
    var awayRank: Int?          // (baseball has no poll; kept so the shared views compile)
    var homeRank: Int?
    var balls = 0, strikes = 0, outs = 0
    var onFirst = false, onSecond = false, onThird = false
    var batter: String?
    var pitcher: String?
    var lastPlay: String?
    var winProbHome: Double?
    var venue: String?
    var broadcast: String?

    func involves(_ abbr: String) -> Bool { away == abbr || home == abbr }
    func opponent(of abbr: String) -> String { away == abbr ? home : away }
    func score(of abbr: String) -> Int { away == abbr ? awayScore : homeScore }
    func rank(of abbr: String) -> Int? { nil }
    var isDelayed: Bool { statusText.lowercased().contains("delay") || statusText.lowercased().contains("suspend") || statusText.lowercased().contains("postpone") }
    var overtime: Bool { period > 9 }
    /// The team at bat: the visitors bat in the top of an inning, the home team in the bottom.
    func isBatting(_ abbr: String) -> Bool { (half == "top" && abbr == away) || (half == "bottom" && abbr == home) }
    /// A runner on second or third: a hit could score him.
    var risp: Bool { onSecond || onThird }
    private func ordinal(_ n: Int) -> String {
        switch n { case 1: return "1st"; case 2: return "2nd"; case 3: return "3rd"; default: return "\(n)th" }
    }
    /// "T3", "B7", "M4", "E4" for the small label beside the zone's icon.
    var chipPeriod: String { (["top": "T", "bottom": "B", "mid": "M", "end": "E"][half] ?? "") + "\(max(1, period))" }
    /// How much of a nine-inning game has been played (extra innings count as full).
    var progress: Double {
        switch state {
        case .pre: return 0
        case .post: return 1
        case .live:
            if period > 9 { return 1 }
            let inning = Double(max(period, 1) - 1), outsShare = Double(min(outs, 3)) / 6
            switch half {
            case "top": return min(1, (inning + outsShare) / 9)
            case "bottom": return min(1, (inning + 0.5 + outsShare) / 9)
            case "mid": return (inning + 0.5) / 9
            case "end": return (inning + 1) / 9
            default: return inning / 9
            }
        }
    }
    var statusLine: String {
        switch state {
        case .pre: return isDelayed ? "Delayed" : Game.kickoff.string(from: date)
        case .post: return overtime ? "Final/\(period)" : "Final"
        case .live:
            if isDelayed { return "Delayed" }
            let word = ["top": "Top", "bottom": "Bot", "mid": "Mid", "end": "End"][half] ?? "Inning"
            return "\(word) \(ordinal(max(1, period)))"
        }
    }
    static let kickoff: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    static let dayShort: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
}

struct StandingRow: Identifiable {
    let team: String            // abbreviation
    var overall = "0-0"
    var conf = ""
    var pct = ".000"
    var gb = "-"
    var l10 = "-"
    var wins = 0, losses = 0, confWins = 0, confLosses = 0, pf = 0, pa = 0
    var streak = "—"
    var id: String { team }
    var diff: Int { pf - pa }
}
struct ConferenceTable: Identifiable { let name: String; var rows: [StandingRow]; var id: String { name } }
struct RankedTeam: Identifiable { let rank: Int; let team: String; let record: String; var id: Int { rank } }

// MARK: - Store

/// Everything the zone shows comes from ESPN's public ESPN's public MLB feed (free, unofficial): teams and conferences,
/// conference standings, the AP Top 25, weekly scoreboards with live play-by-play details, and each team's season schedule.
/// It is fetched online while the zone runs and cached on disk, so the zone still works offline.
final class BaseballStore: ObservableObject {
    static let shared = BaseballStore()

    @Published var teams: [Team] = []
    @Published var conferences: [String] = []
    @Published var standings: [ConferenceTable] = []
    @Published var top25: [RankedTeam] = []
    @Published var boards: [Int: [Game]] = [:]
    @Published var schedules: [String: [Game]] = [:]
    @Published var logoRevision = 0
    @Published var updated: Date?
    @Published var offline = false
    private var extraTeams: [String: Team] = [:]

    // Settings (saved)
    @Published var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "mb.favorites"); loadSchedules() } }
    @Published var showLogos: Bool { didSet { UserDefaults.standard.set(showLogos, forKey: "mb.logos") } }
    @Published var rotateSeconds: Double { didSet { UserDefaults.standard.set(rotateSeconds, forKey: "mb.rotate") } }
    @Published var chipEnabled: Bool { didSet { UserDefaults.standard.set(chipEnabled, forKey: "mb.chip") } }
    /// Run alert: "off", "hr" (home runs only) or "all" (every run).
    @Published var alertMode: String { didSet { UserDefaults.standard.set(alertMode, forKey: "mb.alertMode") } }
    @Published var alertOthers: Bool { didSet { UserDefaults.standard.set(alertOthers, forKey: "mb.alertOthers") } }
    @Published var alertSeconds: Double { didSet { UserDefaults.standard.set(alertSeconds, forKey: "mb.alertSeconds") } }
    /// "zone" (the zone itself opens bigger), "window" (a separate card), or "both".
    @Published var alertStyle: String { didSet { UserDefaults.standard.set(alertStyle, forKey: "mb.alertStyle") } }
    @Published var scoreEvent: ScoreAlertInfo?

    private var logos: [String: NSImage] = [:]
    private var loadingLogos: Set<String> = []
    private var timer: Timer?
    private var lastBoardFetch = Date.distantPast
    private var lastScores: [String: (Int, Int)] = [:]
    private let fixtures: URL? = ProcessInfo.processInfo.environment["MLB_FIXTURES"].map { URL(fileURLWithPath: $0) }
    static var appCanOpenZones: Bool { (Int(Bundle.main.infoDictionary?["BaseballundleVersion"] as? String ?? "") ?? 0) >= 20 }
    static let boardQuery = ""
    private static let site = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb"
    private static let apiV2 = "https://site.api.espn.com/apis/v2/sports/baseball/mlb"
    static let conferenceOrder = ["AL East", "AL Central", "AL West", "NL East", "NL Central", "NL West"]


    init() {
        let d = UserDefaults.standard
        favorites = d.stringArray(forKey: "mb.favorites") ?? []
        showLogos = d.object(forKey: "mb.logos") as? Bool ?? true
        rotateSeconds = d.object(forKey: "mb.rotate") as? Double ?? 8
        chipEnabled = d.object(forKey: "mb.chip") as? Bool ?? true
        alertMode = d.string(forKey: "mb.alertMode") ?? "hr"
        alertOthers = d.object(forKey: "mb.alertOthers") as? Bool ?? false
        alertSeconds = d.object(forKey: "mb.alertSeconds") as? Double ?? 10
        alertStyle = d.string(forKey: "mb.alertStyle") ?? "zone"
    }

    // MARK: Start / polling

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        loadTeams()
        refreshBoard()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    /// Every 15 s: refresh fast (about every 20 s) only while one of your games is live or about to start, otherwise every 5 min.
    private func tick() {
        if Date().timeIntervalSince(lastBoardFetch) >= (hasActiveFavoriteGame ? 20 : 300) { refreshBoard() }
    }
    var hasActiveFavoriteGame: Bool {
        (boards[0] ?? []).contains { g in
            favorites.contains { g.involves($0) } && (g.state == .live || (g.state == .pre && g.date.timeIntervalSinceNow < 1800 && g.date.timeIntervalSinceNow > -600))
        }
    }

    // MARK: Files and downloads

    static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Zones/Baseball", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fetch(_ urlString: String, cacheName: String, maxAge: TimeInterval, completion: @escaping (Data?) -> Void) {
        if let fixtures, let data = try? Data(contentsOf: fixtures.appendingPathComponent(cacheName)) { completion(data); return }
        let file = Self.cacheFolder.appendingPathComponent(cacheName)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        if maxAge > 0, let modified = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(modified) < maxAge, let data = try? Data(contentsOf: file) { completion(data); return }
        guard fixtures == nil, let url = URL(string: urlString) else { completion(try? Data(contentsOf: file)); return }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("Zones-Baseball/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                if let data, (response as? HTTPURLResponse)?.statusCode == 200 { try? data.write(to: file); self.offline = false; completion(data) }
                else { self.offline = true; completion(try? Data(contentsOf: file)) }
            }
        }.resume()
    }
    private func json(_ data: Data?) -> [String: Any]? { data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }

    // MARK: Teams, conferences, standings

    private static func shortConference(_ name: String) -> String {
        name.replacingOccurrences(of: "American League", with: "AL").replacingOccurrences(of: "National League", with: "NL")
    }

    private func loadTeams() {
        // Colours and logos come from the general team list; conference membership and records from the standings.
        fetch("\(Self.site)/teams?limit=500", cacheName: "teams.json", maxAge: 7 * 24 * 3600) { [weak self] teamData in
            guard let self else { return }
            var colors: [String: String] = [:]
            if let root = self.json(teamData), let list = (((root["sports"] as? [[String: Any]])?.first?["leagues"] as? [[String: Any]])?.first?["teams"] as? [[String: Any]]) {
                for t in list { if let t = t["team"] as? [String: Any], let id = t["id"] as? String {
                    var c = t["color"] as? String ?? ""; if c.uppercased() == "FFFFFF" || c.isEmpty { c = t["alternateColor"] as? String ?? "444444" }
                    colors[id] = c
                } }
            }
            self.fetch("\(Self.apiV2)/standings?level=3", cacheName: "standings.json", maxAge: 1800) { data in
                guard let root = self.json(data) else { return }
                var teams: [Team] = [], tables: [ConferenceTable] = []
                func walk(_ node: [String: Any], conference: String) {
                    if let entries = (node["standings"] as? [String: Any])?["entries"] as? [[String: Any]] {
                        let group = Self.shortConference(node["name"] as? String ?? conference)
                        var rows: [StandingRow] = []
                        for e in entries {
                            guard let t = e["team"] as? [String: Any], let id = t["id"] as? String, let abbr = t["abbreviation"] as? String else { continue }
                            let logo = ((t["logos"] as? [[String: Any]])?.first?["href"] as? String).flatMap(URL.init(string:))
                            let school = t["shortDisplayName"] as? String ?? t["location"] as? String ?? abbr
                            teams.append(Team(abbr: abbr, espnID: id, school: school, name: t["displayName"] as? String ?? school, nick: t["name"] as? String ?? "",
                                              conference: group, colorHex: colors[id] ?? "444444", logoURL: logo))
                            var row = StandingRow(team: abbr)
                            for s in (e["stats"] as? [[String: Any]] ?? []) {
                                let type = s["type"] as? String ?? "", dv = s["displayValue"] as? String ?? "", v = Int((s["value"] as? Double) ?? 0)
                                switch type {
                                case "total": row.overall = dv
                                case "winpercent": row.pct = dv
                                case "gamesbehind": row.gb = dv
                                case "lasttengames": row.l10 = dv
                                case "pointsfor" where row.pf == 0: row.pf = v
                                case "pointsagainst" where row.pa == 0: row.pa = v
                                case "streak" where row.streak == "—": row.streak = dv
                                default: break
                                }
                            }
                            let o = row.overall.split(separator: "-").compactMap { Int($0) }, c = row.conf.split(separator: "-").compactMap { Int($0) }
                            if o.count >= 2 { row.wins = o[0]; row.losses = o[1] }
                            if c.count >= 2 { row.confWins = c[0]; row.confLosses = c[1] }
                            rows.append(row)
                        }
                        if let i = tables.firstIndex(where: { $0.name == group }) { tables[i].rows += rows } else { tables.append(ConferenceTable(name: group, rows: rows)) }
                    }
                    for child in (node["children"] as? [[String: Any]] ?? []) { walk(child, conference: conference) }
                }
                for child in (root["children"] as? [[String: Any]] ?? []) { walk(child, conference: Self.shortConference(child["name"] as? String ?? "")) }
                for i in tables.indices { tables[i].rows.sort { Double($0.wins) / Double(max(1, $0.wins + $0.losses)) > Double($1.wins) / Double(max(1, $1.wins + $1.losses)) } }
                tables.sort { (Self.conferenceOrder.firstIndex(of: $0.name) ?? 99, $0.name) < (Self.conferenceOrder.firstIndex(of: $1.name) ?? 99, $1.name) }
                self.standings = tables
                self.conferences = tables.map(\.name)
                self.teams = teams.sorted { ($0.conference, $0.school) < ($1.conference, $1.school) }
                self.favorites = self.favorites.filter { f in self.teams.contains { $0.abbr == f } }
                self.loadSchedules()
            }
        }
    }
    func team(_ abbr: String) -> Team? { teams.first { $0.abbr == abbr } ?? extraTeams[abbr] }
    func teams(in conference: String) -> [Team] { teams.filter { $0.conference == conference } }
    func standing(for abbr: String) -> StandingRow? { standings.flatMap { $0.rows }.first { $0.team == abbr } }

    private func loadRankings() {
        fetch("\(Self.site)/rankings", cacheName: "rankings.json", maxAge: 1800) { [weak self] data in
            guard let self, let root = self.json(data), let poll = (root["rankings"] as? [[String: Any]])?.first, let ranks = poll["ranks"] as? [[String: Any]] else { return }
            self.top25 = ranks.compactMap { r in
                guard let n = r["current"] as? Int, let a = (r["team"] as? [String: Any])?["abbreviation"] as? String else { return nil }
                return RankedTeam(rank: n, team: a, record: r["recordSummary"] as? String ?? "")
            }.sorted { $0.rank < $1.rank }
        }
    }
    func rank(of abbr: String) -> Int? { top25.first { $0.team == abbr }?.rank }

    // MARK: Live board and weeks

    var currentBoard: [Game] { boards[0] ?? [] }
    func board(day: Int) -> [Game] { boards[day] ?? [] }
    func refreshBoard() { lastBoardFetch = Date(); loadDay(0) }

    /// Loads one day of games. `offset` 0 is today (the day ESPN reports as current); -1 is yesterday, 1 is tomorrow.
    func loadDay(_ offset: Int) {
        if offset != 0, let cached = boards[offset], !cached.isEmpty, cached.allSatisfy({ $0.state == .post }) { return }
        let url: String, name: String
        if offset == 0 { url = "\(Self.site)/scoreboard\(Self.boardQuery)"; name = "scoreboard.json" }
        else {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
            let d = f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date())
            url = "\(Self.site)/scoreboard\(Self.boardQuery)\(Self.boardQuery.isEmpty ? "?" : "&")dates=\(d)"; name = "day\(d).json"
        }
        let maxAge: TimeInterval = offset < 0 ? 24 * 3600 : offset > 0 ? 1800 : 0
        fetch(url, cacheName: name, maxAge: maxAge) { [weak self] data in
            guard let self, let root = self.json(data) else { return }
            let games = (root["events"] as? [[String: Any]] ?? []).compactMap { self.game(fromESPN: $0) }
            self.boards[offset] = games
            if offset == 0 { self.updated = Date(); self.detectScores(games) }
            for g in games { for a in [g.away, g.home] { self.loadLogo(a) } }
        }
    }

    /// One game from an ESPN event (scoreboard or team schedule); also remembers opponents outside the main list.
    func game(fromESPN e: [String: Any]) -> Game? {
        guard let id = e["id"] as? String, let comp = (e["competitions"] as? [[String: Any]])?.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let homeC = competitors.first(where: { $0["homeAway"] as? String == "home" }), let awayC = competitors.first(where: { $0["homeAway"] as? String == "away" }),
              let homeT = homeC["team"] as? [String: Any], let awayT = awayC["team"] as? [String: Any],
              let homeAbbr = homeT["abbreviation"] as? String, let awayAbbr = awayT["abbreviation"] as? String else { return nil }
        for t in [homeT, awayT] { remember(t) }
        let status = (comp["status"] as? [String: Any]) ?? (e["status"] as? [String: Any]) ?? [:]
        let type = status["type"] as? [String: Any] ?? [:]
        let stateName = type["state"] as? String ?? "pre"
        // ESPN sends UTC times like "2026-09-21T00:20Z" (no seconds).
        let utc = DateFormatter(); utc.locale = Locale(identifier: "en_US_POSIX"); utc.timeZone = TimeZone(identifier: "UTC"); utc.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        let date = ((comp["date"] as? String ?? e["date"] as? String).flatMap { utc.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }) ?? Date()
        var g = Game(id: id, date: date, state: stateName == "in" ? .live : stateName == "post" ? .post : .pre, away: awayAbbr, home: homeAbbr)
        g.period = status["period"] as? Int ?? 0
        g.statusText = type["shortDetail"] as? String ?? type["description"] as? String ?? ""
        if g.state == .live {
            let d = (type["shortDetail"] as? String ?? type["detail"] as? String ?? "").lowercased()
            g.half = d.hasPrefix("top") ? "top" : d.hasPrefix("bot") ? "bottom" : d.hasPrefix("mid") ? "mid" : d.hasPrefix("end") ? "end" : ""
        }
        func score(_ c: [String: Any]) -> Int {
            if let s = c["score"] as? String { return Int(s) ?? 0 }
            if let s = c["score"] as? [String: Any] { return Int((s["value"] as? Double) ?? Double(s["displayValue"] as? String ?? "") ?? 0) }
            return 0
        }
        g.homeScore = score(homeC); g.awayScore = score(awayC)
        func number(_ c: [String: Any], _ key: String) -> Int { (c[key] as? Int) ?? Int(c[key] as? String ?? "") ?? 0 }
        g.homeHits = number(homeC, "hits"); g.awayHits = number(awayC, "hits"); g.homeErrors = number(homeC, "errors"); g.awayErrors = number(awayC, "errors")
        func record(_ c: [String: Any]) -> String? { ((c["records"] as? [[String: Any]])?.first?["summary"]) as? String }
        g.homeRecord = record(homeC); g.awayRecord = record(awayC)
        g.venue = (comp["venue"] as? [String: Any])?["fullName"] as? String
        g.broadcast = ((comp["broadcasts"] as? [[String: Any]])?.first?["names"] as? [String])?.joined(separator: ", ")
        if let s = comp["situation"] as? [String: Any] {
            g.balls = s["balls"] as? Int ?? 0; g.strikes = s["strikes"] as? Int ?? 0; g.outs = s["outs"] as? Int ?? 0
            func on(_ key: String) -> Bool { (s[key] as? Bool) ?? (s[key] is [String: Any]) }
            g.onFirst = on("onFirst"); g.onSecond = on("onSecond"); g.onThird = on("onThird")
            func player(_ key: String) -> String? { ((s[key] as? [String: Any])?["athlete"] as? [String: Any])?["shortName"] as? String }
            g.batter = player("batter"); g.pitcher = player("pitcher")
            if let last = s["lastPlay"] as? [String: Any] {
                g.lastPlay = last["text"] as? String
                g.winProbHome = (last["probability"] as? [String: Any])?["homeWinPercentage"] as? Double
            }
        }
        return g
    }
    /// Keeps the name, colour and logo of a team that isn't in the FBS list (an FCS opponent), so its games still read properly.
    private func remember(_ t: [String: Any]) {
        guard let abbr = t["abbreviation"] as? String, extraTeams[abbr] == nil, !teams.contains(where: { $0.abbr == abbr }) else { return }
        let logo = (t["logo"] as? String) ?? ((t["logos"] as? [[String: Any]])?.first?["href"] as? String)
        extraTeams[abbr] = Team(abbr: abbr, espnID: t["id"] as? String ?? "", school: t["shortDisplayName"] as? String ?? t["location"] as? String ?? abbr,
                                name: t["displayName"] as? String ?? abbr, nick: t["name"] as? String ?? "", conference: "",
                                colorHex: t["color"] as? String ?? "444444", logoURL: logo.flatMap(URL.init(string:)))
    }

    // MARK: A team's season

    func loadSchedules() { for a in favorites { loadSchedule(a) } }
    func loadSchedule(_ abbr: String) {
        guard let t = team(abbr), !t.espnID.isEmpty else { return }
        fetch("\(Self.site)/teams/\(t.espnID)/schedule", cacheName: "schedule_\(t.espnID).json", maxAge: 1800) { [weak self] data in
            guard let self, let root = self.json(data) else { return }
            self.schedules[abbr] = (root["events"] as? [[String: Any]] ?? []).compactMap { self.game(fromESPN: $0) }.sorted { $0.date < $1.date }
        }
    }
    /// A fuller copy of a game (with live details) from this week's board if one exists.
    func fresh(_ g: Game) -> Game { currentBoard.first { $0.id == g.id } ?? g }
    func games(for abbr: String) -> [Game] { (schedules[abbr] ?? []).map { fresh($0) } }

    /// The game a team's card shows: its live game, else this week's (or the next) game, else its latest result.
    func currentGame(for abbr: String) -> Game? {
        if let g = currentBoard.first(where: { $0.involves(abbr) && $0.state == .live }) { return g }
        if let g = currentBoard.first(where: { $0.involves(abbr) }), g.state == .pre || g.date.timeIntervalSinceNow > -8 * 3600 { return g }
        let sched = schedules[abbr] ?? []
        if let next = sched.first(where: { $0.state != .post }) { return next }
        return sched.last ?? currentBoard.first { $0.involves(abbr) }
    }
    /// The game a corner icon should track.
    var trackedGame: (game: Game, team: Team)? {
        for a in favorites { if let g = currentBoard.first(where: { $0.involves(a) && $0.state == .live }), let t = team(a) { return (g, t) } }
        for a in favorites { if let g = currentBoard.first(where: { $0.involves(a) && $0.state == .pre && $0.date.timeIntervalSinceNow < 1800 && $0.date.timeIntervalSinceNow > -600 }), let t = team(a) { return (g, t) } }
        return nil
    }

    // MARK: Score alerts

    // MARK: Alerts

    /// Compares each live game's score with the last poll; a rise means runs scored.
    private func detectScores(_ games: [Game]) {
        for g in games where g.state != .pre {
            defer { lastScores[g.id] = (g.awayScore, g.homeScore) }
            guard let old = lastScores[g.id], g.state == .live else { continue }   // the first sight of a game is only a baseline
            for (abbr, delta) in [(g.away, g.awayScore - old.0), (g.home, g.homeScore - old.1)] where delta > 0 { announce(g, team: abbr, runs: delta) }
        }
    }
    private func announce(_ g: Game, team: String, runs: Int) {
        guard alertMode != "off" else { return }
        let text = (g.lastPlay ?? "").lowercased()
        let homer = text.contains("homer") || text.contains("home run") || text.contains("grand slam")
        if alertMode == "hr" && !homer { return }
        guard alertOthers || favorites.contains(g.away) || favorites.contains(g.home) else { return }
        let kind = homer ? (runs >= 4 ? "GRAND SLAM" : "HOME RUN") : runs == 1 ? "RUN SCORES" : "\(runs) RUNS SCORE"
        showAlert(ScoreAlertInfo(kind: kind, team: team, points: runs, game: g))
    }
    /// Shows an alert the way the user chose. If the app can't open the zone itself, the separate card is used instead.
    func showAlert(_ info: ScoreAlertInfo) {
        let inZone = (alertStyle == "zone" || alertStyle == "both") && Self.appCanOpenZones
        if inZone {
            scoreEvent = info
            NotificationCenter.default.post(name: Notification.Name("ZonesOpenZoneRequest"), object: nil, userInfo: ["title": "MLB Baseball", "detailed": true, "silent": true])
        }
        if alertStyle == "window" || alertStyle == "both" || !inZone { BaseballScoreAlert.shared.show(info) }
    }

    // MARK: Logos (loaded online, cached on disk; never bundled)

    func logo(_ abbr: String) -> NSImage? {
        guard showLogos else { return nil }
        if let image = logos[abbr] { return image }
        loadLogo(abbr)
        return nil
    }
    func loadLogo(_ abbr: String) {
        guard showLogos, logos[abbr] == nil, !loadingLogos.contains(abbr), let url = team(abbr)?.logoURL else { return }
        loadingLogos.insert(abbr)
        let folder = Self.cacheFolder.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(abbr.replacingOccurrences(of: "/", with: "_")).png")
        DispatchQueue.global(qos: .utility).async {
            var image = NSImage(contentsOf: file)
            if image == nil, self.fixtures == nil, let data = try? Data(contentsOf: url), let downloaded = NSImage(data: data) { try? data.write(to: file); image = downloaded }
            if image == nil, let fixtures = self.fixtures { image = NSImage(contentsOf: fixtures.appendingPathComponent("logos/\(abbr).png")) }
            DispatchQueue.main.async {
                self.loadingLogos.remove(abbr)
                if let image { self.logos[abbr] = image; self.logoRevision += 1 }
            }
        }
    }
}

// MARK: - Small shared views

/// A school's logo (loaded online) on a light disc so dark logos stay visible on a dark background, or a badge in the school's
/// colours with its abbreviation if logos are off or unavailable.
struct TeamLogo: View {
    @ObservedObject var store = BaseballStore.shared
    let abbr: String
    var size: CGFloat = 40
    var body: some View {
        let _ = store.logoRevision
        if let image = store.logo(abbr) {
            ZStack {
                Circle().fill(Color.white.opacity(0.93))
                Image(nsImage: image).resizable().scaledToFit().frame(width: size * 0.82, height: size * 0.82)
            }.frame(width: size, height: size)
        } else {
            ZStack {
                Circle().fill(store.team(abbr)?.color ?? .gray)
                Text(abbr).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.4).lineLimit(1)
            }.frame(width: size, height: size)
        }
    }
}

/// "#3" in front of a ranked school's name.
struct RankTag: View {
    let rank: Int?
    var size: CGFloat = 10
    var body: some View {
        if let rank { Text("#\(rank)").font(.system(size: size, weight: .heavy).monospacedDigit()).foregroundStyle(.secondary) }
    }
}
