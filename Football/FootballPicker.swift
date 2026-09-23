import AppKit
import SwiftUI

// How NFL Football plugs into the shared team picker (../Shared/SportsPicker.swift).

extension Team: PickerTeam {
    var pickKey: String { abbr }
    var pickAbbr: String { abbr }
    var pickName: String { name }
    var pickShort: String { nick }
    var pickGroup: String { division }
    var pickColor: Color { color }
    var pickSearchText: String { "\(name) \(nick) \(abbr) \(division)" }
}

extension FootballStore: PickerStore {
    var pickTeams: [Team] { teams }
    var pickGroups: [PickerGroup] {
        FootballStore.divisions.enumerated().map { i, d in
            PickerGroup(name: d, short: d, color: i < 4 ? Color(hue: 0.0 + Double(i) * 0.03, saturation: 0.55, brightness: 0.65) : Color(hue: 0.6 + Double(i - 4) * 0.03, saturation: 0.55, brightness: 0.65))
        }
    }
    var pickRings: Int { 4 }
    var pickNoun: String { "team" }
    var pickExtraFilters: [(name: String, keys: Set<String>)] {
        [("AFC", Set(teams.filter { $0.conference == "AFC" }.map(\.abbr))), ("NFC", Set(teams.filter { $0.conference == "NFC" }.map(\.abbr)))]
    }
    func pickLogo(_ key: String) -> NSImage? { logo(key) }
    func pickSubtitle(_ key: String) -> String {
        let t = team(key), s = standings.first { $0.team.abbr == key }
        return "\(t?.division ?? "")\(s.map { " · \($0.record)" } ?? "")"
    }
    func pickNext(_ key: String) -> String? {
        guard let g = currentGame(for: key) else { return nil }
        return "\(g.state == .post ? "Last" : "Next"): \(g.home == key ? "vs" : "@") \(team(g.opponent(of: key))?.nick ?? g.opponent(of: key)) · \(g.statusLine)"
    }
    func pickOpen(_ key: String) { FootballDetailsController.shared.show(team: key, game: currentGame(for: key)) }
}
