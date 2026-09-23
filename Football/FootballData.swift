import AppKit
import SwiftUI

// MARK: - Models

struct Team: Identifiable, Hashable {
    let abbr: String
    let name: String
    let nick: String
    let conference: String
    let division: String
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
    var week: Int
    var date: Date
    var state: State
    var period = 0
    var clock = ""
    var clockSeconds = 0.0
    var statusText = ""
    var away: String
    var home: String
    var awayScore = 0
    var homeScore = 0
    var awayRecord: String?
    var homeRecord: String?
    var possession: String?
    var downDistance: String?
    var yardLine: Int?            // yards from the home team's goal line (0 = home end zone, 100 = away end zone)
    var redZone = false
    var homeTimeouts: Int?
    var awayTimeouts: Int?
    var lastPlay: String?
    var winProbHome: Double?
    var venue: String?
    var broadcast: String?
    var overtime = false

    func involves(_ abbr: String) -> Bool { away == abbr || home == abbr }
    func opponent(of abbr: String) -> String { away == abbr ? home : away }
    func score(of abbr: String) -> Int { away == abbr ? awayScore : homeScore }
    var isDelayed: Bool { statusText.lowercased().contains("delay") }
    /// How much of a 60-minute regulation game has been played (overtime counts as full).
    var progress: Double {
        switch state {
        case .pre: return 0
        case .post: return 1
        case .live:
            if period > 4 { return 1 }
            return max(0, min(1, (Double(max(period, 1) - 1) * 900 + (900 - clockSeconds)) / 3600))
        }
    }
    /// "Q3 4:32", "Halftime", "Final", "Sun 1:00 PM"…
    var statusLine: String {
        switch state {
        case .pre: return Game.kickoff.string(from: date)
        case .post: return overtime || period > 4 ? "Final/OT" : "Final"
        case .live:
            if isDelayed { return "Delayed" }
            if period == 2 && clockSeconds <= 0 && statusText.lowercased().contains("half") { return "Halftime" }
            let q = period > 4 ? "OT" : "Q\(period)"
            return "\(q) \(clock)"
        }
    }
    static let kickoff: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()
}

struct TeamStanding: Identifiable {
    let team: Team
    var w = 0, l = 0, t = 0, pf = 0, pa = 0
    var homeW = 0, homeL = 0, awayW = 0, awayL = 0, divW = 0, divL = 0
    var last: [Bool] = []            // most recent results, oldest first (true = win)
    var id: String { team.abbr }
    var games: Int { w + l + t }
    var pct: Double { games == 0 ? 0 : (Double(w) + 0.5 * Double(t)) / Double(games) }
    var record: String { t > 0 ? "\(w)-\(l)-\(t)" : "\(w)-\(l)" }
    var diff: Int { pf - pa }
    var streak: String {
        guard let latest = last.last else { return "—" }
        let n = last.reversed().prefix { $0 == latest }.count
        return "\(latest ? "W" : "L")\(n)"
    }
}

// MARK: - Store

/// Everything the zone shows comes from here: open nflverse data for teams, schedules and past scores,
/// plus ESPN's public scoreboard feed for live games. Both are fetched online while the zone runs and cached
/// on disk so the zone still works offline.
final class FootballStore: ObservableObject {
    static let shared = FootballStore()

    @Published var teams: [Team] = []
    @Published var season: [Game] = []
    @Published var boards: [Int: [Game]] = [:]
    @Published var currentWeek = 1
    @Published var seasonYear = Calendar.current.component(.year, from: Date())
    @Published var logoRevision = 0
    @Published var updated: Date?
    @Published var offline = false

    // Settings (saved)
    @Published var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "fb.favorites") } }
    @Published var showLogos: Bool { didSet { UserDefaults.standard.set(showLogos, forKey: "fb.logos") } }
    @Published var rotateSeconds: Double { didSet { UserDefaults.standard.set(rotateSeconds, forKey: "fb.rotate") } }
    @Published var chipEnabled: Bool { didSet { UserDefaults.standard.set(chipEnabled, forKey: "fb.chip") } }
    /// Score pop-up: "off", "td" (touchdowns only) or "all" (every scoring play).
    @Published var alertMode: String { didSet { UserDefaults.standard.set(alertMode, forKey: "fb.alertMode") } }
    @Published var alertOthers: Bool { didSet { UserDefaults.standard.set(alertOthers, forKey: "fb.alertOthers") } }
    @Published var alertSeconds: Double { didSet { UserDefaults.standard.set(alertSeconds, forKey: "fb.alertSeconds") } }
    /// Where the score alert appears: "zone" (the zone itself opens bigger), "window" (a separate card), or "both".
    @Published var alertStyle: String { didSet { UserDefaults.standard.set(alertStyle, forKey: "fb.alertStyle") } }
    /// Set when someone scores; the zone's own view reacts to it.
    @Published var scoreEvent: ScoreAlertInfo?
    private var lastScores: [String: (Int, Int)] = [:]
    /// Zones builds from 20 on can be asked to open a zone (the same way Media opens for a new song).
    static var appCanOpenZones: Bool { (Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0) >= 20 }

    private var logos: [String: NSImage] = [:]
    private var loadingLogos: Set<String> = []
    private var timer: Timer?
    private var lastBoardFetch = Date.distantPast
    /// Tests can point the store at local copies of the data instead of the internet.
    private let fixtures: URL? = ProcessInfo.processInfo.environment["FB_FIXTURES"].map { URL(fileURLWithPath: $0) }

    static let teamsURL = URL(string: "https://raw.githubusercontent.com/nflverse/nflfastR-data/master/teams_colors_logos.csv")!
    static let gamesURL = URL(string: "https://github.com/nflverse/nfldata/raw/master/data/games.csv")!
    static let divisions = ["AFC East", "AFC North", "AFC South", "AFC West", "NFC East", "NFC North", "NFC South", "NFC West"]

    init() {
        let d = UserDefaults.standard
        favorites = d.stringArray(forKey: "fb.favorites") ?? []
        showLogos = d.object(forKey: "fb.logos") as? Bool ?? true
        rotateSeconds = d.object(forKey: "fb.rotate") as? Double ?? 8
        chipEnabled = d.object(forKey: "fb.chip") as? Bool ?? true
        alertMode = d.string(forKey: "fb.alertMode") ?? "td"
        alertOthers = d.object(forKey: "fb.alertOthers") as? Bool ?? false
        alertSeconds = d.object(forKey: "fb.alertSeconds") as? Double ?? 10
        alertStyle = d.string(forKey: "fb.alertStyle") ?? "zone"
    }

    // MARK: Start / polling

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        loadTeamsAndSeason()
        refreshBoard()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    /// Every 15 s: refresh fast (about every 20 s) only while one of your games is live or about to start, otherwise every 5 min.
    private func tick() {
        let interval: TimeInterval = hasActiveFavoriteGame ? 20 : 300
        if Date().timeIntervalSince(lastBoardFetch) >= interval { refreshBoard() }
    }
    var hasActiveFavoriteGame: Bool {
        (boards[currentWeek] ?? []).contains { g in
            favorites.contains { g.involves($0) } && (g.state == .live || (g.state == .pre && g.date.timeIntervalSinceNow < 1800 && g.date.timeIntervalSinceNow > -600))
        }
    }

    // MARK: Files and downloads

    static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Zones/Football", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    /// Returns the freshest data it can: from the internet if the cached copy is old, else the cache; the cache also covers being offline.
    private func fetch(_ url: URL, cacheName: String, maxAge: TimeInterval, completion: @escaping (Data?) -> Void) {
        if let fixtures, let data = try? Data(contentsOf: fixtures.appendingPathComponent(cacheName)) { completion(data); return }
        let file = Self.cacheFolder.appendingPathComponent(cacheName)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        if maxAge > 0, let modified = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(modified) < maxAge, let data = try? Data(contentsOf: file) { completion(data); return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Zones-Football/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                    try? data.write(to: file); self.offline = false; completion(data)
                } else {
                    self.offline = true; completion(try? Data(contentsOf: file))
                }
            }
        }.resume()
    }

    // MARK: Teams and season (nflverse)

    private func loadTeamsAndSeason() {
        fetch(Self.gamesURL, cacheName: "games.csv", maxAge: 6 * 3600) { [weak self] data in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { return }
            let rows = Self.parseCSV(text)
            let latest = rows.compactMap { Int($0["season"] ?? "") }.max() ?? self.seasonYear
            let games = rows.filter { Int($0["season"] ?? "") == latest }.compactMap(Self.game(fromCSV:))
            self.seasonYear = latest
            self.season = games
            self.fetch(Self.teamsURL, cacheName: "teams.csv", maxAge: 7 * 24 * 3600) { teamData in
                guard let teamData, let teamText = String(data: teamData, encoding: .utf8) else { return }
                let active = Set(games.flatMap { [$0.home, $0.away] })
                self.teams = Self.parseCSV(teamText).compactMap { r -> Team? in
                    guard let abbr = r["team_abbr"], active.contains(abbr) else { return nil }
                    return Team(abbr: abbr, name: r["team_name"] ?? abbr, nick: r["team_nick"] ?? abbr, conference: r["team_conf"] ?? "",
                                division: r["team_division"] ?? "", colorHex: r["team_color"] ?? "#444444", logoURL: URL(string: r["team_logo_espn"] ?? ""))
                }.sorted { $0.name < $1.name }
                if self.favorites.isEmpty == false { self.favorites = self.favorites.filter { f in self.teams.contains { $0.abbr == f } } }
            }
        }
    }

    static func game(fromCSV r: [String: String]) -> Game? {
        guard let id = r["game_id"], let away = r["away_team"], let home = r["home_team"], let week = Int(r["week"] ?? ""), r["game_type"] == "REG" else { return nil }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd HH:mm"
        let date = f.date(from: "\(r["gameday"] ?? "") \((r["gametime"] ?? "").isEmpty ? "13:00" : r["gametime"]!)") ?? Date.distantFuture
        let done = !(r["home_score"] ?? "").isEmpty && !(r["away_score"] ?? "").isEmpty
        var g = Game(id: id, week: week, date: date, state: done ? .post : .pre, away: away, home: home)
        g.awayScore = Int(r["away_score"] ?? "") ?? 0; g.homeScore = Int(r["home_score"] ?? "") ?? 0
        g.overtime = (r["overtime"] ?? "0") == "1"
        g.venue = r["stadium"]
        return g
    }

    static func parseCSV(_ text: String) -> [[String: String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        func next() -> Unicode.Scalar? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let c = next() {
            if quoted {
                if c == "\"" { if let n = next() { if n == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { field.unicodeScalars.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" { row.append(field); field = ""; rows.append(row); row = [] }
            else if c == "\r" { continue }
            else { field.unicodeScalars.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().filter { $0.count >= header.count - 2 && $0.count > 1 }.map { r in
            var d: [String: String] = [:]
            for (i, h) in header.enumerated() where i < r.count { d[h] = r[i] }
            return d
        }
    }

    // MARK: Live board (ESPN public scoreboard)

    private static func normalize(_ abbr: String) -> String {
        switch abbr { case "WSH": "WAS"; case "LAR": "LA"; case "JAC": "JAX"; default: abbr }
    }

    func refreshBoard() {
        lastBoardFetch = Date()
        loadWeek(nil)
    }

    /// `week == nil` loads the current week (the one ESPN reports as current).
    func loadWeek(_ week: Int?) {
        var comps = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!
        if let week { comps.queryItems = [URLQueryItem(name: "dates", value: String(seasonYear)), URLQueryItem(name: "seasontype", value: "2"), URLQueryItem(name: "week", value: String(week))] }
        let name = week.map { "week\($0).json" } ?? "scoreboard.json"
        // Past weeks never change, so they may be cached for a long time; the current week always refreshes.
        let maxAge: TimeInterval = (week != nil && week! < currentWeek) ? 24 * 3600 : 0
        fetch(comps.url!, cacheName: name, maxAge: maxAge) { [weak self] data in
            guard let self, let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let number = ((root["week"] as? [String: Any])?["number"] as? Int) ?? week ?? self.currentWeek
            let games = (root["events"] as? [[String: Any]] ?? []).compactMap { Self.game(fromESPN: $0, week: number) }
            self.boards[number] = games
            if week == nil { self.currentWeek = number; self.updated = Date(); self.detectScores(games) }
            for g in games { for abbr in [g.away, g.home] { self.loadLogo(abbr) } }
        }
    }

    /// Compares each live game's score with the last poll; a rise means someone scored.
    private func detectScores(_ games: [Game]) {
        for g in games where g.state != .pre {
            let key = "\(g.week)-\(g.away)-\(g.home)"
            defer { lastScores[key] = (g.awayScore, g.homeScore) }
            guard let old = lastScores[key], g.state == .live else { continue }   // the first sight of a game is only a baseline
            for (abbr, delta) in [(g.away, g.awayScore - old.0), (g.home, g.homeScore - old.1)] where delta > 0 { announce(g, team: abbr, points: delta) }
        }
    }
    private func announce(_ g: Game, team: String, points: Int) {
        guard alertMode != "off", points >= 2 else { return }          // a lone extra point is part of the touchdown
        if alertMode == "td" && points < 6 { return }
        guard alertOthers || favorites.contains(g.away) || favorites.contains(g.home) else { return }
        let kind = points >= 6 ? "TOUCHDOWN" : points == 3 ? "FIELD GOAL" : "SAFETY"
        showAlert(ScoreAlertInfo(kind: kind, team: team, points: points, game: g))
    }
    /// Shows a score alert the way the user chose. If the app can't open the zone itself, the separate card is used instead.
    func showAlert(_ info: ScoreAlertInfo) {
        let inZone = (alertStyle == "zone" || alertStyle == "both") && Self.appCanOpenZones
        if inZone {
            scoreEvent = info
            NotificationCenter.default.post(name: Notification.Name("ZonesOpenZoneRequest"), object: nil,
                                            userInfo: ["title": "NFL Football", "detailed": true, "silent": true])
        }
        if alertStyle == "window" || alertStyle == "both" || !inZone { FBScoreAlert.shared.show(info) }
    }

    static func game(fromESPN e: [String: Any], week: Int) -> Game? {
        guard let id = e["id"] as? String, let comp = (e["competitions"] as? [[String: Any]])?.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let homeC = competitors.first(where: { $0["homeAway"] as? String == "home" }), let awayC = competitors.first(where: { $0["homeAway"] as? String == "away" }),
              let homeT = homeC["team"] as? [String: Any], let awayT = awayC["team"] as? [String: Any],
              let homeAbbr = (homeT["abbreviation"] as? String).map(normalize), let awayAbbr = (awayT["abbreviation"] as? String).map(normalize) else { return nil }
        let status = e["status"] as? [String: Any] ?? [:]
        let type = status["type"] as? [String: Any] ?? [:]
        let stateName = type["state"] as? String ?? "pre"
        // ESPN sends UTC times like "2026-09-21T00:20Z" (no seconds).
        let utc = DateFormatter(); utc.locale = Locale(identifier: "en_US_POSIX"); utc.timeZone = TimeZone(identifier: "UTC"); utc.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        let date = ((e["date"] as? String).flatMap { utc.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }) ?? Date()
        var g = Game(id: id, week: week, date: date, state: stateName == "in" ? .live : stateName == "post" ? .post : .pre, away: awayAbbr, home: homeAbbr)
        g.period = status["period"] as? Int ?? 0
        g.clock = status["displayClock"] as? String ?? ""
        g.clockSeconds = (status["clock"] as? Double) ?? Double(status["clock"] as? Int ?? 0)
        g.statusText = type["shortDetail"] as? String ?? type["description"] as? String ?? ""
        g.homeScore = Int(homeC["score"] as? String ?? "") ?? 0; g.awayScore = Int(awayC["score"] as? String ?? "") ?? 0
        func record(_ c: [String: Any]) -> String? { ((c["records"] as? [[String: Any]])?.first?["summary"]) as? String }
        g.homeRecord = record(homeC); g.awayRecord = record(awayC)
        g.venue = (comp["venue"] as? [String: Any])?["fullName"] as? String
        g.broadcast = ((comp["broadcasts"] as? [[String: Any]])?.first?["names"] as? [String])?.joined(separator: ", ")
        g.overtime = g.period > 4
        if let s = comp["situation"] as? [String: Any] {
            g.downDistance = s["shortDownDistanceText"] as? String ?? s["downDistanceText"] as? String
            g.redZone = s["isRedZone"] as? Bool ?? false
            g.homeTimeouts = s["homeTimeouts"] as? Int; g.awayTimeouts = s["awayTimeouts"] as? Int
            g.yardLine = s["yardLine"] as? Int
            if let p = s["possession"] as? String { g.possession = p == (homeT["id"] as? String) ? homeAbbr : p == (awayT["id"] as? String) ? awayAbbr : nil }
            if let last = s["lastPlay"] as? [String: Any] {
                g.lastPlay = last["text"] as? String
                g.winProbHome = (last["probability"] as? [String: Any])?["homeWinPercentage"] as? Double
            }
        }
        return g
    }

    // MARK: Queries

    func team(_ abbr: String) -> Team? { teams.first { $0.abbr == abbr } }
    var currentBoard: [Game] { boards[currentWeek] ?? [] }
    func board(week: Int) -> [Game] { boards[week] ?? season.filter { $0.week == week } }

    /// The game to show for a team: its live game, else today's/this week's game, else the next one, else the latest result.
    func currentGame(for abbr: String) -> Game? {
        if let g = currentBoard.first(where: { $0.involves(abbr) && $0.state == .live }) { return g }
        let thisWeek = currentBoard.first { $0.involves(abbr) }
        let upcoming = season.filter { $0.involves(abbr) && $0.state == .pre }.sorted { $0.date < $1.date }.first
        if let t = thisWeek, t.state == .pre || t.date.timeIntervalSinceNow > -6 * 3600 { return t }
        if let u = upcoming { return board(week: u.week).first { $0.involves(abbr) } ?? u }
        return thisWeek ?? season.filter { $0.involves(abbr) && $0.state == .post }.max { $0.date < $1.date }
    }
    func games(for abbr: String) -> [Game] {
        season.filter { $0.involves(abbr) }.map { g in board(week: g.week).first { $0.away == g.away && $0.home == g.home } ?? g }.sorted { $0.date < $1.date }
    }

    /// The game a corner icon should track: a favorite that is live, else one starting within 30 minutes.
    var trackedGame: (game: Game, team: Team)? {
        for abbr in favorites {
            if let g = currentBoard.first(where: { $0.involves(abbr) && $0.state == .live }), let t = team(abbr) { return (g, t) }
        }
        for abbr in favorites {
            if let g = currentBoard.first(where: { $0.involves(abbr) && $0.state == .pre && $0.date.timeIntervalSinceNow < 1800 && $0.date.timeIntervalSinceNow > -600 }), let t = team(abbr) { return (g, t) }
        }
        return nil
    }

    var standings: [TeamStanding] {
        var table: [String: TeamStanding] = [:]
        for t in teams { table[t.abbr] = TeamStanding(team: t) }
        // The nflverse and ESPN game ids differ, so a game is matched by week and teams; ESPN's copy is fresher.
        let finals = season.map { g in board(week: g.week).first { $0.away == g.away && $0.home == g.home } ?? g }.filter { $0.state == .post }.sorted { $0.date < $1.date }
        for g in finals {
            guard var a = table[g.away], var h = table[g.home] else { continue }
            a.pf += g.awayScore; a.pa += g.homeScore; h.pf += g.homeScore; h.pa += g.awayScore
            let sameDivision = a.team.division == h.team.division
            if g.awayScore == g.homeScore { a.t += 1; h.t += 1 }
            else {
                let awayWon = g.awayScore > g.homeScore
                if awayWon { a.w += 1; a.awayW += 1; h.l += 1; h.homeL += 1; if sameDivision { a.divW += 1; h.divL += 1 } }
                else { h.w += 1; h.homeW += 1; a.l += 1; a.awayL += 1; if sameDivision { h.divW += 1; a.divL += 1 } }
                a.last.append(awayWon); h.last.append(!awayWon)
            }
            table[g.away] = a; table[g.home] = h
        }
        return Array(table.values)
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
        let file = folder.appendingPathComponent("\(abbr).png")
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

/// A team's logo (loaded online) on a light disc so dark logos stay visible on a dark background, or a badge in the
/// team's colours with its abbreviation if logos are off or unavailable.
struct TeamLogo: View {
    @ObservedObject var store = FootballStore.shared
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
                Text(abbr).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            }.frame(width: size, height: size)
        }
    }
}
