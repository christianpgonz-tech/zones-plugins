import AppKit
import SwiftUI

enum CMode { case entry, pie, favorites, search, networkCalc, numberSystems }

/// Everything the zone and its settings window share: the chosen category and units, the amount, favorites and the current screen.
final class Conv: ObservableObject {
    static let shared = Conv()
    enum Side { case from, to }

    /// Remembers "I was on Favorites" (separately from which converter/category) so reopening the zone can return there,
    /// when the "last converter I used" setting is on.
    @Published var mode: CMode = .entry { didSet { if mode == .favorites || mode == .entry { UserDefaults.standard.set(mode == .favorites, forKey: "cv.lastWasFavorites") } } }
    /// Where search was opened from (a calculator tool, or the plain converter) — search is reachable from either, so
    /// going back from it needs to know which one to return to, not always the plain converter.
    @Published var searchReturnMode: CMode = .entry
    @Published var category: String
    @Published var active: Side = .from            // which box typing goes into
    @Published var fromText = "1"
    @Published var toText = "0"
    @Published var picking: Side?                 // the unit list is open for From or To
    @Published var query = ""                     // the unit list's search
    @Published var searchQuery = ""               // the all-units search
    @Published var copied = false
    @Published var copiedSide: Side = .from
    @Published var favUnits: [String] { didSet { UserDefaults.standard.set(favUnits, forKey: "cv.favUnits") } }
    @Published var favPairs: [String] { didSet { UserDefaults.standard.set(favPairs, forKey: "cv.favPairs") } }
    /// A category favorited directly (from Settings), independent of any unit starred inside it.
    @Published var favCategories: [String] { didSet { UserDefaults.standard.set(favCategories, forKey: "cv.favCategories") } }
    @Published private var chosen: [String: [String]] { didSet { UserDefaults.standard.set(chosen, forKey: "cv.chosen") } }
    @Published var rates = Rates.shared
    private var ratesObserver: Any?

    init() {
        let d = UserDefaults.standard
        category = d.string(forKey: "cv.category") ?? "Length"
        favUnits = d.stringArray(forKey: "cv.favUnits") ?? []
        favPairs = d.stringArray(forKey: "cv.favPairs") ?? []
        favCategories = d.stringArray(forKey: "cv.favCategories") ?? []
        chosen = d.dictionary(forKey: "cv.chosen") as? [String: [String]] ?? [:]
        rates.load()
        ratesObserver = rates.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.objectWillChange.send(); self?.recompute() } }
        recompute()
    }

    // MARK: Categories and units

    var categories: [CCategory] { Catalog.fixed + [rates.category()] }
    var current: CCategory { categories.first { $0.id == category } ?? Catalog.length }

    var fromID: String { validUnit(chosen[current.id]?.first) ?? defaultPair(current).0 }
    var toID: String { validUnit(chosen[current.id]?.dropFirst().first) ?? defaultPair(current).1 }
    private func validUnit(_ id: String?) -> String? { id.flatMap { id in current.units.contains { $0.id == id } ? id : nil } }
    private func defaultPair(_ c: CCategory) -> (String, String) {
        switch c.id {
        case "Length": return ("km", "mi"); case "Temperature": return ("C", "F"); case "Area": return ("m2", "ft2"); case "Volume": return ("L", "gal")
        case "Weight": return ("kg", "lb"); case "Time": return ("h", "min"); case "Pressure": return ("bar", "psi"); case "Speed": return ("kph", "mph")
        case "Energy": return ("kcal", "kJ"); case "Currency": return c.units.contains { $0.id == "CLP" } ? ("USD", "CLP") : (c.units.first?.id ?? "", c.units.last?.id ?? "")
        case "Force": return ("N", "lbf"); case "Acceleration": return ("mps2", "g"); case "Torque": return ("Nm", "ftlbf")
        case "Density": return ("kgm3", "gcm3"); case "Illuminance": return ("lux", "fc"); case "Power": return ("W", "hp")
        case "Angle": return ("deg", "rad"); case "Data": return ("MB", "GB"); case "Fuel Economy": return ("mpgus", "L100km")
        case "Resistance": return ("ohm", "kohm"); case "Capacitance": return ("uF", "nF")
        case "Current": return ("mA", "A"); case "Voltage": return ("V", "mV"); case "Frequency": return ("MHz", "GHz")
        case "Data Rate": return ("Mbps", "MBps"); case "Network Latency": return ("ms", "km_fiber"); case "Flow Rate": return ("Lmin", "gpm")
        case "Viscosity": return ("cP", "Pas"); case "Print Resolution": return ("px", "in300"); case "Focal Length": return ("apsc", "mm")
        case "Shoe Size": return ("us", "eu")
        case "Angular Velocity": return ("rpm", "rads"); case "Battery Energy": return ("mah37", "Wh"); case "Video Storage Rate": return ("mbps", "GBh")
        default: return (c.units.first?.id ?? "", c.units.last?.id ?? "")
        }
    }
    var from: CUnit? { current.units.first { $0.id == fromID } }
    var to: CUnit? { current.units.first { $0.id == toID } }

    /// Opens a category's converter.
    func select(category id: String) {
        category = id; UserDefaults.standard.set(id, forKey: "cv.category")
        picking = nil; query = ""; searchQuery = ""; mode = .entry
        recompute()
    }
    func set(_ side: Side, _ unit: String) {
        var pair = [fromID, toID]
        pair[side == .from ? 0 : 1] = unit
        chosen[current.id] = pair
        recompute()
    }
    func swap() { chosen[current.id] = [toID, fromID]; recompute() }
    func setPair(category id: String, from a: String, to b: String) { chosen[id] = [a, b] }

    // MARK: Both sides — either one can be typed into

    func text(_ side: Side) -> String { side == .from ? fromText : toText }
    private func setText(_ side: Side, _ t: String) { if side == .from { fromText = t } else { toText = t } }

    /// Makes a box the one typing goes into. Its text is stripped of grouping separators so it edits cleanly.
    func focus(_ side: Side) {
        guard active != side else { return }
        active = side
        let t = text(side).replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
        setText(side, t == "—" ? "0" : t)
    }
    /// Recomputes the inactive side from whatever was just typed into the active one.
    func recompute() {
        guard let a = from, let b = to else { return }
        if active == .from {
            if let v = Double(fromText.replacingOccurrences(of: ",", with: ".")) { toText = Convert.format(Convert.value(v, from: a, to: b), currency: current.id == "Currency") }
            else { toText = "—" }
        } else {
            if let v = Double(toText.replacingOccurrences(of: ",", with: ".")) { fromText = Convert.format(Convert.value(v, from: b, to: a), currency: current.id == "Currency") }
            else { fromText = "—" }
        }
    }

    // MARK: Favorites

    func unitKey(_ cat: String, _ id: String) -> String { "\(cat)|\(id)" }
    func isFav(_ id: String, in cat: String? = nil) -> Bool { favUnits.contains(unitKey(cat ?? current.id, id)) }
    /// Does this category have at least one favorited unit inside it? Drives the small star badge on its pie slice.
    func categoryHasFavorite(_ cat: String) -> Bool { favCategories.contains(cat) || favUnits.contains { $0.hasPrefix("\(cat)|") } }
    func toggleCategoryFav(_ cat: String) { if favCategories.contains(cat) { favCategories.removeAll { $0 == cat } } else { favCategories.append(cat) } }
    func toggleFav(_ id: String, in cat: String? = nil) {
        let k = unitKey(cat ?? current.id, id)
        if let i = favUnits.firstIndex(of: k) { favUnits.remove(at: i) } else { favUnits.append(k) }
    }
    var pairKey: String { "\(current.id)|\(fromID)|\(toID)" }
    var pairIsFav: Bool { favPairs.contains(pairKey) }
    func togglePair() { if let i = favPairs.firstIndex(of: pairKey) { favPairs.remove(at: i) } else { favPairs.append(pairKey) } }
    func addPair(_ cat: String, _ a: String, _ b: String) { let k = "\(cat)|\(a)|\(b)"; if a != b, !favPairs.contains(k) { favPairs.append(k) } }
    func openPair(_ key: String) {
        let p = key.split(separator: "|").map(String.init)
        guard p.count == 3 else { return }
        setPair(category: p[0], from: p[1], to: p[2]); select(category: p[0])
    }
    /// A saved pair as text: "🇺🇸 USD → 🇨🇱 CLP".
    func label(pair key: String) -> (category: String, from: String, to: String)? {
        let p = key.split(separator: "|").map(String.init)
        guard p.count == 3, let c = categories.first(where: { $0.id == p[0] }), let a = c.units.first(where: { $0.id == p[1] }), let b = c.units.first(where: { $0.id == p[2] }) else { return nil }
        func text(_ u: CUnit) -> String { (u.flag.map { $0 + " " } ?? "") + u.symbol }
        return (c.id, text(a), text(b))
    }
    /// Units for the open list: favorites first (A–Z), then everything else A–Z; the search filters both.
    var pickList: (favorites: [CUnit], others: [CUnit]) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = current.units.filter { Self.matches($0, q) }
        let sorted = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (sorted.filter { isFav($0.id) }, sorted.filter { !isFav($0.id) })
    }
    static func matches(_ u: CUnit, _ q: String) -> Bool {
        q.isEmpty || u.name.lowercased().contains(q) || u.symbol.lowercased().contains(q) || u.id.lowercased().contains(q) || u.aliases.contains { $0.lowercased().contains(q) }
    }
    /// The all-units search: any unit in any category.
    var searchResults: [(category: String, unit: CUnit)] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return categories.flatMap { c in c.units.filter { Self.matches($0, q) }.map { (c.id, $0) } }
            .sorted { ($0.unit.name.lowercased().hasPrefix(q) ? 0 : 1, $0.unit.name) < ($1.unit.name.lowercased().hasPrefix(q) ? 0 : 1, $1.unit.name) }
    }
    /// Typing a category's own name (like "temperature" or "data") jumps straight to it, no unit needed.
    var categoryMatches: [CCategory] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return categories.filter { $0.id.lowercased().contains(q) }
    }
    func pick(searchResult r: (category: String, unit: CUnit)) {
        select(category: r.category); set(.from, r.unit.id)
    }

    func copy(_ side: Side) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text(side).replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: ""), forType: .string)
        copied = true; copiedSide = side
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.copied = false }
    }

    // MARK: Keyboard (returns true when the key was used)

    func key(_ k: String) -> Bool {
        if mode == .search {
            switch k {
            case "⎋": if !searchQuery.isEmpty { searchQuery = "" } else { mode = .pie }
            case "⌫": if !searchQuery.isEmpty { searchQuery.removeLast() }
            case "↩": if let c = categoryMatches.first { select(category: c.id) } else if let first = searchResults.first { pick(searchResult: first) }
            default: if searchQuery.count < 24 { searchQuery += k }
            }
            return true
        }
        if picking != nil {
            switch k {
            case "⎋": if !query.isEmpty { query = "" } else { picking = nil }
            case "⌫": if !query.isEmpty { query.removeLast() }
            case "↩": if let first = (pickList.favorites + pickList.others).first, let side = picking { set(side, first.id); picking = nil; query = "" }
            default: if query.count < 24 { query += k }
            }
            return true
        }
        if mode == .pie || mode == .favorites {
            if k == "⎋" { if mode == .favorites { mode = .pie; return true } }
            return false
        }
        var t = text(active)
        switch k {
        case "0"..."9": t = (t == "0" || t == "—") ? k : (t.count < 16 ? t + k : t)
        case ".", ",": if !t.contains(".") { t += t.isEmpty || t == "-" ? "0." : "." }
        case "-": t = t.hasPrefix("-") ? String(t.dropFirst()) : "-" + t
        case "⌫": t = t.count <= 1 ? "0" : String(t.dropLast()); if t == "-" { t = "0" }
        case "⎋": t = "0"
        case "↩": copy(active == .from ? .to : .from); return true
        case "\t": focus(active == .from ? .to : .from); return true
        default: return false
        }
        setText(active, t); recompute()
        return true
    }
}
