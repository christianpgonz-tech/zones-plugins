import AppKit
import SwiftUI

// MARK: - Leagues, teams, matches

struct League: Identifiable, Hashable {
    let code: String        // ESPN's league code
    let name: String
    let short: String
    let colorHex: String
    let flag: String        // the country's flag
    var id: String { code }
    var color: Color { Color(hex: colorHex) }
    static let all = [League(code: "eng.1", name: "Premier League", short: "EPL", colorHex: "#8B3FD9", flag: "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"),
                      League(code: "esp.1", name: "La Liga", short: "La Liga", colorHex: "#E0483D", flag: "\u{1F1EA}\u{1F1F8}"),
                      League(code: "usa.1", name: "MLS", short: "MLS", colorHex: "#2F7BE0", flag: "\u{1F1FA}\u{1F1F8}")]
    static func named(_ code: String) -> League { all.first { $0.code == code } ?? all[0] }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        if s.count != 6 { s = "444444" }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

struct Team: Identifiable, Hashable {
    let key: String         // "eng.1:349" — unique across leagues
    let league: String
    let teamID: String
    let name: String
    let short: String
    let abbr: String
    let colorHex: String
    let logoURL: URL?
    var id: String { key }
    var color: Color { Color(hex: colorHex) }
}

struct MatchEvent: Identifiable, Hashable {
    enum Kind { case goal, penaltyGoal, ownGoal, yellow, red }
    let id: Int
    let kind: Kind
    let minute: String
    let seconds: Double
    let teamID: String
    let player: String
    var isGoal: Bool { kind == .goal || kind == .penaltyGoal || kind == .ownGoal }
    var isCard: Bool { kind == .yellow || kind == .red }
    /// "Haaland 9'", "Haaland 9' (P)", "Haaland 9' (OG)"
    var text: String { "\(player) \(minute)" + (kind == .penaltyGoal ? " (P)" : kind == .ownGoal ? " (OG)" : "") }
}

struct Match: Identifiable, Hashable {
    enum State { case pre, live, post }
    let id: String
    let league: String
    var date: Date
    var state: State
    var period = 0
    var clockSeconds = 0.0
    var clock = ""
    var statusName = ""
    var statusText = ""
    var home: String          // team keys
    var away: String
    var homeID = ""
    var awayID = ""
    var homeScore = 0
    var awayScore = 0
    var events: [MatchEvent] = []
    var venue: String?
    var broadcast: String?

    func involves(_ key: String) -> Bool { home == key || away == key }
    func opponent(of key: String) -> String { home == key ? away : home }
    func score(of key: String) -> Int { home == key ? homeScore : awayScore }
    var isHalftime: Bool { statusName.uppercased().contains("HALFTIME") }
    var isDelayed: Bool { statusName.uppercased().contains("DELAY") || statusName.uppercased().contains("SUSPEND") }
    func teamID(for key: String) -> String { home == key ? homeID : awayID }
    func cards(for teamID: String, red: Bool) -> Int { events.filter { $0.teamID == teamID && $0.kind == (red ? .red : .yellow) }.count }
    var goals: [MatchEvent] { events.filter { $0.isGoal } }
    var redCards: Int { events.filter { $0.kind == .red }.count }

    /// Which half is being played (1, 2, or 3 = extra time / penalties).
    var half: Int { state == .pre ? 0 : (period >= 3 ? 3 : max(1, period)) }
    /// How far through the current half: 0...1 (a half is 45 minutes; anything beyond that is stoppage time, shown as "+N'").
    var halfProgress: Double {
        switch state {
        case .pre: return 0
        case .post: return 1
        case .live:
            if isHalftime { return 1 }
            let minutes = clockSeconds / 60
            switch half {
            case 1: return max(0, min(1, minutes / 45))
            case 2: return max(0, min(1, (minutes - 45) / 45))
            default: return max(0, min(1, (minutes - 90) / 30))
            }
        }
    }
    /// The whole match against 90 minutes (used by the small corner dial).
    var totalProgress: Double { state == .pre ? 0 : state == .post ? 1 : max(0, min(1, clockSeconds / 5400)) }
    /// The "+3'" shown when a half runs past its 45 minutes.
    var stoppage: String? {
        guard state == .live, let plus = clock.range(of: "+") else { return nil }
        return String(clock[plus.lowerBound...]).replacingOccurrences(of: "'", with: "")
    }
    var statusLine: String {
        switch state {
        case .pre: return Match.kickoff.string(from: date)
        case .post: return statusText.isEmpty ? "FT" : (statusText.uppercased().contains("PEN") ? "Pens" : statusText.uppercased().contains("AET") ? "AET" : "FT")
        case .live: return isDelayed ? "Delayed" : isHalftime ? "HT" : clock
        }
    }
    static let kickoff: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()
}

struct StandingRow: Identifiable {
    let teamKey: String
    var rank = 0, played = 0, w = 0, d = 0, l = 0, gf = 0, ga = 0, pts = 0
    var id: String { teamKey }
    var gd: Int { gf - ga }
}
struct StandingGroup: Identifiable { let name: String; var rows: [StandingRow]; var id: String { name } }

// MARK: - Store

/// Everything the zone shows comes from ESPN's public soccer feed (free, unofficial): teams, live scores with goal and card
/// events, fixtures and results, and league tables. It is fetched online while the zone runs and cached on disk.
final class SoccerStore: ObservableObject {
    static let shared = SoccerStore()

    @Published var teams: [Team] = []
    @Published var boards: [String: [Match]] = [:]            // league code → current matches (live and around today)
    @Published var days: [String: [Match]] = [:]              // "yyyyMMdd|league" → matches on that day
    @Published var schedules: [String: [Match]] = [:]         // team key → season results and fixtures
    @Published var standings: [String: [StandingGroup]] = [:]
    @Published var logoRevision = 0
    @Published var leagueLogos: [String: URL] = [:]
    @Published var updated: Date?
    @Published var offline = false

    // Settings (saved)
    @Published var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "sc.favorites"); loadSchedules() } }
    @Published var showLogos: Bool { didSet { UserDefaults.standard.set(showLogos, forKey: "sc.logos") } }
    @Published var rotateSeconds: Double { didSet { UserDefaults.standard.set(rotateSeconds, forKey: "sc.rotate") } }
    @Published var chipEnabled: Bool { didSet { UserDefaults.standard.set(chipEnabled, forKey: "sc.chip") } }
    /// "off", "goals", or "goalscards" (goals and red cards).
    @Published var alertMode: String { didSet { UserDefaults.standard.set(alertMode, forKey: "sc.alertMode") } }
    @Published var alertOthers: Bool { didSet { UserDefaults.standard.set(alertOthers, forKey: "sc.alertOthers") } }
    @Published var alertSeconds: Double { didSet { UserDefaults.standard.set(alertSeconds, forKey: "sc.alertSeconds") } }
    /// "zone" (the zone itself opens bigger), "window" (a separate card), or "both".
    @Published var alertStyle: String { didSet { UserDefaults.standard.set(alertStyle, forKey: "sc.alertStyle") } }
    @Published var scoreEvent: ScoreAlertInfo?
    /// A team key that scored in the last minute (drives a subtle pulse on the corner dial).
    @Published var recentGoal: [String: Date] = [:]

    private var logos: [String: NSImage] = [:]
    private var loadingLogos: Set<String> = []
    private var timer: Timer?
    private var lastBoardFetch = Date.distantPast
    private var lastSeen: [String: (Int, Int, Int)] = [:]      // match id → home, away, red cards
    private let fixtures: URL? = ProcessInfo.processInfo.environment["SC_FIXTURES"].map { URL(fileURLWithPath: $0) }
    static var appCanOpenZones: Bool { (Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0) >= 20 }
    private static let base = "https://site.api.espn.com/apis/site/v2/sports/soccer"

    init() {
        let d = UserDefaults.standard
        favorites = d.stringArray(forKey: "sc.favorites") ?? []
        showLogos = d.object(forKey: "sc.logos") as? Bool ?? true
        rotateSeconds = d.object(forKey: "sc.rotate") as? Double ?? 8
        chipEnabled = d.object(forKey: "sc.chip") as? Bool ?? true
        alertMode = d.string(forKey: "sc.alertMode") ?? "goals"
        alertOthers = d.object(forKey: "sc.alertOthers") as? Bool ?? false
        alertSeconds = d.object(forKey: "sc.alertSeconds") as? Double ?? 10
        alertStyle = d.string(forKey: "sc.alertStyle") ?? "zone"
    }

    // MARK: Start / polling

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        loadTeams { [weak self] in self?.loadSchedules() }
        for l in League.all { loadStandings(l.code) }
        refreshBoards()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func tick() {
        let interval: TimeInterval = hasActiveFavoriteMatch ? 20 : 300
        if Date().timeIntervalSince(lastBoardFetch) >= interval { refreshBoards() }
    }
    var allBoard: [Match] { boards.values.flatMap { $0 } }
    var hasActiveFavoriteMatch: Bool {
        allBoard.contains { m in favorites.contains { m.involves($0) } && (m.state == .live || (m.state == .pre && m.date.timeIntervalSinceNow < 1800 && m.date.timeIntervalSinceNow > -600)) }
    }

    // MARK: Files and downloads

    static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Zones/Soccer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fetch(_ urlString: String, cacheName: String, maxAge: TimeInterval, completion: @escaping (Data?) -> Void) {
        if let fixtures, let data = try? Data(contentsOf: fixtures.appendingPathComponent(cacheName)) { completion(data); return }
        let file = Self.cacheFolder.appendingPathComponent(cacheName)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        if maxAge > 0, let modified = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(modified) < maxAge, let data = try? Data(contentsOf: file) { completion(data); return }
        guard fixtures == nil, let url = URL(string: urlString) else { completion(try? Data(contentsOf: file)); return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Zones-Soccer/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                if let data, (response as? HTTPURLResponse)?.statusCode == 200 { try? data.write(to: file); self.offline = false; completion(data) }
                else { self.offline = true; completion(try? Data(contentsOf: file)) }
            }
        }.resume()
    }
    private func json(_ data: Data?) -> [String: Any]? { data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }

    // MARK: Teams

    private func loadTeams(done: @escaping () -> Void) {
        var pending = League.all.count
        for l in League.all {
            fetch("\(Self.base)/\(l.code)/teams", cacheName: "teams_\(l.code).json", maxAge: 7 * 24 * 3600) { [weak self] data in
                guard let self else { return }
                if let root = self.json(data), let list = (((root["sports"] as? [[String: Any]])?.first?["leagues"] as? [[String: Any]])?.first?["teams"] as? [[String: Any]]) {
                    let parsed = list.compactMap { ($0["team"] as? [String: Any]).flatMap { Self.team(from: $0, league: l.code) } }
                    self.teams.removeAll { $0.league == l.code }
                    self.teams.append(contentsOf: parsed)
                    self.teams.sort { ($0.league, $0.name) < ($1.league, $1.name) }
                    self.favorites = self.favorites.filter { f in self.teams.contains { $0.key == f } || !self.teams.contains { $0.league == f.split(separator: ":").first.map(String.init) } }
                }
                pending -= 1; if pending == 0 { done() }
            }
        }
    }
    static func team(from t: [String: Any], league: String) -> Team? {
        guard let id = t["id"] as? String, let name = t["displayName"] as? String else { return nil }
        var color = t["color"] as? String ?? "444444"
        if color.uppercased() == "FFFFFF" || color.isEmpty { color = t["alternateColor"] as? String ?? "444444" }
        let logo = ((t["logos"] as? [[String: Any]])?.first?["href"] as? String) ?? (t["logo"] as? String)
        return Team(key: "\(league):\(id)", league: league, teamID: id, name: name, short: t["shortDisplayName"] as? String ?? name,
                    abbr: t["abbreviation"] as? String ?? String(name.prefix(3)).uppercased(), colorHex: color, logoURL: logo.flatMap(URL.init(string:)))
    }
    func team(_ key: String) -> Team? { teams.first { $0.key == key } }
    func teams(in league: String) -> [Team] { teams.filter { $0.league == league } }

    // MARK: Matches (scoreboard)

    func refreshBoards() {
        lastBoardFetch = Date()
        for l in League.all {
            fetch("\(Self.base)/\(l.code)/scoreboard", cacheName: "scoreboard_\(l.code).json", maxAge: 0) { [weak self] data in
                guard let self, let root = self.json(data) else { return }
                if let logo = (((root["leagues"] as? [[String: Any]])?.first?["logos"] as? [[String: Any]])?.first?["href"] as? String).flatMap(URL.init(string:)) {
                    self.leagueLogos[l.code] = logo; self.loadLogo("league:\(l.code)")
                }
                let matches = (root["events"] as? [[String: Any]] ?? []).compactMap { Self.match(from: $0, league: l.code) }
                self.boards[l.code] = matches
                self.updated = Date()
                self.detect(matches)
                for m in matches { for k in [m.home, m.away] { self.loadLogo(k) } }
            }
        }
    }
    private static let dayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f }()
    /// Matches on one calendar day for one league. The feed only answers one day at a time, so a range is a run of these.
    func loadDay(_ date: Date, league: String) {
        let day = Self.dayFormat.string(from: date)
        let key = "\(day)|\(league)"
        let isToday = Calendar.current.isDateInToday(date)
        if days[key] != nil && !isToday { return }
        fetch("\(Self.base)/\(league)/scoreboard?dates=\(day)", cacheName: "day_\(league)_\(day).json", maxAge: isToday ? 0 : 6 * 3600) { [weak self] data in
            guard let self, let root = self.json(data) else { return }
            self.days[key] = (root["events"] as? [[String: Any]] ?? []).compactMap { Self.match(from: $0, league: league) }
            for m in self.days[key] ?? [] { for k in [m.home, m.away] { self.loadLogo(k) } }
        }
    }
    /// Loads every day from `offsets.lowerBound` to `offsets.upperBound` days from today, for the given leagues (skipping days already loaded).
    func loadRange(_ offsets: Range<Int>, leagues: [League]) {
        let start = Calendar.current.startOfDay(for: Date())
        var delay = 0.0
        for off in offsets {
            guard let date = Calendar.current.date(byAdding: .day, value: off, to: start) else { continue }
            for l in leagues where days["\(Self.dayFormat.string(from: date))|\(l.code)"] == nil || off == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.loadDay(date, league: l.code) }
                delay += 0.04                     // spread the requests out a little
            }
        }
    }
    /// Days in the range that are still waiting for an answer.
    func pendingDays(_ offsets: Range<Int>, leagues: [League]) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        return offsets.reduce(0) { total, off in
            guard let date = Calendar.current.date(byAdding: .day, value: off, to: start) else { return total }
            return total + leagues.filter { days["\(Self.dayFormat.string(from: date))|\($0.code)"] == nil }.count
        }
    }
    func day(_ date: Date, league: String) -> [Match] { days["\(Self.dayFormat.string(from: date))|\(league)"] ?? [] }

    /// One match from an ESPN event (scoreboard or team schedule).
    static func match(from e: [String: Any], league: String) -> Match? {
        guard let id = e["id"] as? String, let comp = (e["competitions"] as? [[String: Any]])?.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let homeC = competitors.first(where: { $0["homeAway"] as? String == "home" }), let awayC = competitors.first(where: { $0["homeAway"] as? String == "away" }),
              let homeT = homeC["team"] as? [String: Any], let awayT = awayC["team"] as? [String: Any],
              let homeID = homeT["id"] as? String, let awayID = awayT["id"] as? String else { return nil }
        let status = (comp["status"] as? [String: Any]) ?? (e["status"] as? [String: Any]) ?? [:]
        let type = status["type"] as? [String: Any] ?? [:]
        let stateName = type["state"] as? String ?? "pre"
        let utc = DateFormatter(); utc.locale = Locale(identifier: "en_US_POSIX"); utc.timeZone = TimeZone(identifier: "UTC"); utc.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        let date = ((comp["date"] as? String ?? e["date"] as? String).flatMap { utc.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }) ?? Date()
        var m = Match(id: id, league: league, date: date, state: stateName == "in" ? .live : stateName == "post" ? .post : .pre,
                      home: "\(league):\(homeID)", away: "\(league):\(awayID)")
        m.homeID = homeID; m.awayID = awayID
        m.period = status["period"] as? Int ?? 0
        m.clockSeconds = (status["clock"] as? Double) ?? Double(status["clock"] as? Int ?? 0)
        m.clock = status["displayClock"] as? String ?? ""
        m.statusName = type["name"] as? String ?? ""
        m.statusText = type["shortDetail"] as? String ?? type["detail"] as? String ?? ""
        func score(_ c: [String: Any]) -> Int {
            if let s = c["score"] as? String { return Int(s) ?? 0 }
            if let s = c["score"] as? [String: Any] { return Int((s["value"] as? Double) ?? Double(s["displayValue"] as? String ?? "") ?? 0) }
            return Int(c["score"] as? Double ?? 0)
        }
        m.homeScore = score(homeC); m.awayScore = score(awayC)
        m.venue = (comp["venue"] as? [String: Any])?["fullName"] as? String
        m.broadcast = ((comp["broadcasts"] as? [[String: Any]])?.first?["names"] as? [String])?.joined(separator: ", ")
        var n = 0
        for d in (comp["details"] as? [[String: Any]] ?? []) {
            let scoring = d["scoringPlay"] as? Bool ?? false, red = d["redCard"] as? Bool ?? false, yellow = d["yellowCard"] as? Bool ?? false
            let kind: MatchEvent.Kind
            if scoring { kind = (d["ownGoal"] as? Bool ?? false) ? .ownGoal : (d["penaltyKick"] as? Bool ?? false) ? .penaltyGoal : .goal }
            else if red { kind = .red } else if yellow { kind = .yellow } else { continue }
            let athlete = (d["athletesInvolved"] as? [[String: Any]])?.first
            let clock = d["clock"] as? [String: Any]
            n += 1
            m.events.append(MatchEvent(id: n, kind: kind, minute: clock?["displayValue"] as? String ?? "", seconds: clock?["value"] as? Double ?? 0,
                                       teamID: (d["team"] as? [String: Any])?["id"] as? String ?? "", player: athlete?["shortName"] as? String ?? athlete?["displayName"] as? String ?? "Unknown"))
        }
        return m
    }

    // MARK: Season schedule for a team (results and fixtures)

    func loadSchedules() {
        for key in favorites { loadSchedule(key) }
    }
    func loadSchedule(_ key: String) {
        guard let t = team(key) ?? Optional(Team(key: key, league: String(key.split(separator: ":").first ?? "eng.1"), teamID: String(key.split(separator: ":").last ?? ""), name: key, short: key, abbr: key, colorHex: "444444", logoURL: nil)), !t.teamID.isEmpty else { return }
        var pending = 2
        var all: [Match] = []
        for fixtureFlag in [false, true] {
            let suffix = fixtureFlag ? "?fixture=true" : ""
            fetch("\(Self.base)/\(t.league)/teams/\(t.teamID)/schedule\(suffix)", cacheName: "schedule_\(t.league)_\(t.teamID)\(fixtureFlag ? "_fx" : "").json", maxAge: 1800) { [weak self] data in
                guard let self else { return }
                if let root = self.json(data) { all.append(contentsOf: (root["events"] as? [[String: Any]] ?? []).compactMap { Self.match(from: $0, league: t.league) }) }
                pending -= 1
                if pending == 0 {
                    var seen = Set<String>()
                    self.schedules[key] = all.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
                }
            }
        }
    }

    /// The match a team's card shows: its live match, else today's/next, else its latest result.
    func currentMatch(for key: String) -> Match? {
        if let m = allBoard.first(where: { $0.involves(key) && $0.state == .live }) { return m }
        let sched = schedules[key] ?? []
        let upcoming = sched.first { $0.state != .post && $0.date.timeIntervalSinceNow > -3 * 3600 }
        let latest = sched.last { $0.state == .post }
        if let b = allBoard.first(where: { $0.involves(key) && $0.state == .post && abs($0.date.timeIntervalSinceNow) < 6 * 3600 }) { return b }
        if let u = upcoming, latest == nil || u.date.timeIntervalSinceNow < 4 * 24 * 3600 { return allBoard.first { $0.id == u.id } ?? u }
        return latest ?? upcoming ?? allBoard.first { $0.involves(key) }
    }
    /// A fuller copy of a match (with its events) from the live boards if one exists.
    func fresh(_ m: Match) -> Match { allBoard.first { $0.id == m.id } ?? m }

    /// The match a corner icon should track.
    var trackedMatch: (match: Match, team: Team)? {
        for key in favorites { if let m = allBoard.first(where: { $0.involves(key) && $0.state == .live }), let t = team(key) { return (m, t) } }
        for key in favorites { if let m = allBoard.first(where: { $0.involves(key) && $0.state == .pre && $0.date.timeIntervalSinceNow < 1800 && $0.date.timeIntervalSinceNow > -600 }), let t = team(key) { return (m, t) } }
        return nil
    }

    // MARK: Standings

    func loadStandings(_ league: String) {
        fetch("https://site.api.espn.com/apis/v2/sports/soccer/\(league)/standings", cacheName: "standings_\(league).json", maxAge: 900) { [weak self] data in
            guard let self, let root = self.json(data) else { return }
            self.standings[league] = (root["children"] as? [[String: Any]] ?? []).map { child in
                let entries = ((child["standings"] as? [String: Any])?["entries"] as? [[String: Any]]) ?? []
                var rows: [StandingRow] = entries.compactMap { e in
                    guard let id = (e["team"] as? [String: Any])?["id"] as? String else { return nil }
                    var r = StandingRow(teamKey: "\(league):\(id)")
                    for s in (e["stats"] as? [[String: Any]] ?? []) {
                        let v = Int((s["value"] as? Double) ?? 0)
                        switch s["name"] as? String ?? "" {
                        case "rank": r.rank = v; case "gamesPlayed": r.played = v; case "wins": r.w = v; case "ties": r.d = v; case "losses": r.l = v
                        case "pointsFor": r.gf = v; case "pointsAgainst": r.ga = v; case "points": r.pts = v
                        default: break
                        }
                    }
                    return r
                }
                rows.sort { ($1.pts, $1.gd, $1.gf) < ($0.pts, $0.gd, $0.gf) }
                for i in rows.indices { rows[i].rank = i + 1 }
                return StandingGroup(name: child["name"] as? String ?? League.named(league).name, rows: rows)
            }
        }
    }
    func standing(for key: String) -> StandingRow? {
        let league = String(key.split(separator: ":").first ?? "")
        return standings[league]?.flatMap { $0.rows }.first { $0.teamKey == key }
    }

    // MARK: Goal and card alerts

    private func detect(_ matches: [Match]) {
        for m in matches where m.state != .pre {
            defer { lastSeen[m.id] = (m.homeScore, m.awayScore, m.redCards) }
            guard let old = lastSeen[m.id], m.state == .live else { continue }
            if m.homeScore > old.0 { announce(m, scorerKey: m.home, goal: true) }
            if m.awayScore > old.1 { announce(m, scorerKey: m.away, goal: true) }
            if m.redCards > old.2, alertMode == "goalscards", let card = m.events.last(where: { $0.kind == .red }) {
                announce(m, scorerKey: card.teamID == m.homeID ? m.home : m.away, goal: false)
            }
        }
    }
    private func announce(_ m: Match, scorerKey: String, goal: Bool) {
        if goal { recentGoal[scorerKey] = Date() }
        guard alertMode != "off", alertOthers || favorites.contains(m.home) || favorites.contains(m.away) else { return }
        let tid = m.teamID(for: scorerKey)
        let event = goal ? m.events.last(where: { $0.isGoal && ($0.kind == .ownGoal ? $0.teamID != tid : $0.teamID == tid) }) : m.events.last(where: { $0.kind == .red })
        let kind = !goal ? "RED CARD" : event?.kind == .ownGoal ? "OWN GOAL" : event?.kind == .penaltyGoal ? "PENALTY GOAL" : "GOAL"
        showAlert(ScoreAlertInfo(kind: kind, team: scorerKey, detail: event.map { "\($0.player) \($0.minute)" }, match: m))
    }
    /// Shows an alert the way the user chose. If the app can't open the zone itself, the separate card is used instead.
    func showAlert(_ info: ScoreAlertInfo) {
        let inZone = (alertStyle == "zone" || alertStyle == "both") && Self.appCanOpenZones
        if inZone {
            scoreEvent = info
            NotificationCenter.default.post(name: Notification.Name("ZonesOpenZoneRequest"), object: nil, userInfo: ["title": "Soccer", "detailed": true, "silent": true])
        }
        if alertStyle == "window" || alertStyle == "both" || !inZone { SCScoreAlert.shared.show(info) }
    }

    // MARK: Logos (loaded online, cached on disk; never bundled)

    func logo(_ key: String) -> NSImage? {
        guard showLogos else { return nil }
        if let image = logos[key] { return image }
        loadLogo(key)
        return nil
    }
    func loadLogo(_ key: String) {
        let url = key.hasPrefix("league:") ? leagueLogos[String(key.dropFirst(7))] : team(key)?.logoURL
        guard showLogos, logos[key] == nil, !loadingLogos.contains(key), let url else { return }
        loadingLogos.insert(key)
        let folder = Self.cacheFolder.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = key.replacingOccurrences(of: ":", with: "_")
        let file = folder.appendingPathComponent("\(name).png")
        DispatchQueue.global(qos: .utility).async {
            var image = NSImage(contentsOf: file)
            if image == nil, self.fixtures == nil, let data = try? Data(contentsOf: url), let downloaded = NSImage(data: data) { try? data.write(to: file); image = downloaded }
            if image == nil, let fixtures = self.fixtures { image = NSImage(contentsOf: fixtures.appendingPathComponent("logos/\(name).png")) }
            DispatchQueue.main.async {
                self.loadingLogos.remove(key)
                if let image { self.logos[key] = image; self.logoRevision += 1 }
            }
        }
    }
}

// MARK: - Shared small views

/// A club's logo (loaded online) on a light disc so dark logos stay visible on a dark background, or a badge in the club's
/// colours with its abbreviation if logos are off or unavailable.
struct TeamLogo: View {
    @ObservedObject var store = SoccerStore.shared
    let key: String
    var size: CGFloat = 40
    var body: some View {
        let _ = store.logoRevision
        if let image = store.logo(key) {
            ZStack {
                Circle().fill(Color.white.opacity(0.93))
                Image(nsImage: image).resizable().scaledToFit().frame(width: size * 0.82, height: size * 0.82)
            }.frame(width: size, height: size)
        } else {
            ZStack {
                Circle().fill(store.team(key)?.color ?? .gray)
                Text(store.team(key)?.abbr ?? "?").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            }.frame(width: size, height: size)
        }
    }
}

/// A league's logo (loaded online, on a light disc) with its country flag, and optionally its name.
struct LeagueMark: View {
    @ObservedObject var store = SoccerStore.shared
    let league: League
    var size: CGFloat = 16
    var showName = false
    var showFlag = true
    var body: some View {
        let _ = store.logoRevision
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.white.opacity(0.93))
                if let image = store.logo("league:\(league.code)") { Image(nsImage: image).resizable().scaledToFit().frame(width: size * 0.78, height: size * 0.78) }
                else { Text(String(league.short.prefix(1))).font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(league.color) }
            }.frame(width: size, height: size)
            if showFlag { Text(league.flag).font(.system(size: size * 0.9)) }
            if showName { Text(league.name).font(.system(size: max(9, size * 0.72), weight: .medium)).foregroundStyle(.primary).lineLimit(1) }
        }
    }
}
