import AppKit
import SwiftUI

// How Soccer plugs into the shared team picker (../Shared/SportsPicker.swift).

extension Team: PickerTeam {
    var pickKey: String { key }
    var pickAbbr: String { abbr }
    var pickName: String { name }
    var pickShort: String { short }
    var pickGroup: String { League.named(league).name }
    var pickColor: Color { color }
    var pickSearchText: String { "\(name) \(short) \(abbr) \(League.named(league).name)" }
}

extension SoccerStore: PickerStore {
    var pickTeams: [Team] { teams }
    var pickGroups: [PickerGroup] { League.all.map { PickerGroup(name: $0.name, short: $0.short, color: $0.color) } }
    var pickRings: Int { 4 }
    var pickNoun: String { "club" }
    func pickLogo(_ key: String) -> NSImage? { logo(key) }
    func pickSubtitle(_ key: String) -> String {
        let t = team(key), s = standing(for: key)
        return "\(League.named(t?.league ?? "").name)\(s.map { " · #\($0.rank) · \($0.pts) pts" } ?? "")"
    }
    func pickNext(_ key: String) -> String? {
        guard let m = currentMatch(for: key) else { return nil }
        return "\(m.state == .post ? "Last" : "Next"): \(m.home == key ? "vs" : "@") \(team(m.opponent(of: key))?.short ?? "?") · \(m.statusLine)"
    }
    func pickOpen(_ key: String) { SoccerDetailsController.shared.show(team: key, match: currentMatch(for: key).map { fresh($0) }) }
    private func league(named name: String) -> League? { League.all.first { $0.name == name } }
    func pickGroupLogo(_ group: String) -> NSImage? { league(named: group).flatMap { logo("league:\($0.code)") } }
    func pickGroupFlag(_ group: String) -> String? { league(named: group)?.flag }
}
