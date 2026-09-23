import AppKit
import SwiftUI

// How College Basketball plugs into the shared team picker (../Shared/SportsPicker.swift).

extension Team: PickerTeam {
    var pickKey: String { abbr }
    var pickAbbr: String { abbr }
    var pickName: String { name }
    var pickShort: String { school }
    var pickGroup: String { conference }
    var pickColor: Color { color }
    var pickSearchText: String { "\(name) \(school) \(nick) \(abbr)" }
}

extension CollegeBasketballStore: PickerStore {
    var pickTeams: [Team] { teams }
    var pickGroups: [PickerGroup] {
        conferences.enumerated().map { i, c in
            PickerGroup(name: c, short: ["Big East": "BE", "Independents": "IND", "America East": "AmE", "Big Sky": "BSky", "Big South": "BSth", "Big West": "BW", "Southland": "SLND", "Horizon": "HZN", "Patriot": "PAT", "Summit": "SUM", "Sun Belt": "SBC"][c] ?? c, color: Color(hue: Double(i) / Double(max(1, conferences.count)), saturation: 0.5, brightness: 0.7))
        }
    }
    var pickRings: Int { 9 }
    var pickNoun: String { "school" }
    var pickExtraFilters: [(name: String, keys: Set<String>)] { [("Top 25", Set(top25.map(\.team)))] }
    func pickLogo(_ key: String) -> NSImage? { logo(key) }
    func pickRank(_ key: String) -> Int? { rank(of: key) }
    func pickSubtitle(_ key: String) -> String {
        let t = team(key), s = standing(for: key)
        return "\(t?.conference ?? "")\(s.map { " · \($0.overall) (\($0.conf) conf)" } ?? "")"
    }
    func pickNext(_ key: String) -> String? {
        guard let g = currentGame(for: key) else { return nil }
        return "\(g.state == .post ? "Last" : "Next"): \(g.home == key ? "vs" : "@") \(team(g.opponent(of: key))?.school ?? g.opponent(of: key)) · \(g.statusLine)"
    }
    func pickOpen(_ key: String) { CollegeBasketballDetailsController.shared.show(team: key, game: currentGame(for: key).map { fresh($0) }) }
}
