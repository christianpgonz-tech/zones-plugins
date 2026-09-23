import AppKit
import SwiftUI

/// Tells the wrapper which points belong to the zone's content, so a press on empty space still reaches Zones (that is how an open zone is moved).
final class ConverterHitMap { var contains: (CGPoint) -> Bool = { _ in true } }

let converterGold = Color(red: 1, green: 0.84, blue: 0.04)

/// How much smaller than the 320×270 design the converter screen is actually drawn at, given the zone's real size.
/// Threaded through as an Environment value rather than a `.scaleEffect` transform: a transform scales the *pixels* but
/// SwiftUI/AppKit's hit-testing for a Button under a `scaleEffect` inside an `NSHostingView` is unreliable (this is what
/// made the header's Back/search/gear buttons unclickable — confirmed by two failed workarounds before this rewrite).
/// Multiplying every font size, frame and padding by this value instead means the layout is really laid out at its true
/// final size, so hit-testing is correct everywhere, not just near the transform's center.
private struct ConverterScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var converterScale: CGFloat { get { self[ConverterScaleKey.self] } set { self[ConverterScaleKey.self] = newValue } }
}

/// Whether `p` falls within the dial's actual visible wedge (a quarter-circle at a corner, a half-circle at an edge, the
/// whole circle in Settings) — not just within `geo.radius` of the anchor. A plain distance check approves the *entire*
/// surrounding circle, including the 270° of empty desktop around a corner placement that was never actually part of the
/// zone; that phantom area then swallowed clicks meant to fall through to the app's own background (its drag-to-reposition
/// handling), which is why that only ever seemed to work at edge placements and never at a corner.
private func wedgeContains(_ p: CGPoint, _ geo: FGeo) -> Bool {
    guard hypot(p.x - geo.anchor.x, p.y - geo.anchor.y) <= geo.radius else { return false }
    guard !geo.full else { return true }
    var a = atan2(p.y - geo.anchor.y, p.x - geo.anchor.x) - (geo.facing - geo.span / 2)
    a = a.truncatingRemainder(dividingBy: 2 * .pi); if a < 0 { a += 2 * .pi }
    return a <= geo.span
}

// MARK: - Root

struct ConverterView: View {
    let placement: String
    let hit: ConverterHitMap
    @ObservedObject var model = Conv.shared
    private let design = CGSize(width: 320, height: 270)

    var body: some View {
        GeometryReader { proxy in
            let geo = FGeo(placement: placement, size: proxy.size)
            ZStack(alignment: .topLeading) {
                switch model.mode {
                case .pie:
                    let _ = hit.contains = { p in wedgeContains(p, geo) }
                    // No hub buttons here — Favorites and Settings are wheel slices of their own now (in the
                    // "Converter" section), so a duplicate shortcut in the center would be redundant.
                    RingDial(sections: pieSections, geo: geo, rings: rings(for: geo), persistKey: "cv.pieRotation") { id in openTile(id) }
                case .favorites:
                    let _ = hit.contains = { p in wedgeContains(p, geo) }
                    if favoriteCategoryItems.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "star").font(.system(size: 26)).foregroundStyle(.secondary)
                            Text("No favorites yet").font(.system(size: 16, weight: .semibold))
                            Text("Star a category (or a tool like Networking) and it shows up here.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(width: geo.radius * 1.1).position(geo.point(geo.radius * 0.62, geo.facing))
                    } else {
                        RingDial(sections: [DialSection(name: "", items: favoriteCategoryItems)], geo: geo, rings: rings(for: geo), persistKey: "cv.favRotation") { id in openTile(id) }
                    }
                    hub(geo, leading: (symbol: "square.grid.2x2", title: "All Categories", help: "See every category again", action: { model.mode = .pie }))
                default:
                    // minStep 0.15 hugs the visible edge (same as the sports dials) — 0.5 was leaving a big blank
                    // band between the screen edge and the panel, most visible at a straight top/bottom/left/right
                    // placement where that gap sits in plain view rather than off toward the corner.
                    let fit = geo.bestFit(design: design, margin: 16, minStep: 0.15)
                    let rect = CGRect(x: fit.center.x - design.width * fit.scale / 2, y: fit.center.y - design.height * fit.scale / 2, width: design.width * fit.scale, height: design.height * fit.scale)
                    let _ = hit.contains = { rect.insetBy(dx: -6, dy: -6).contains($0) }
                    Panel(model: model)
                        .frame(width: rect.width, height: rect.height, alignment: .top)
                        .position(fit.center)
                        .environment(\.converterScale, fit.scale)
                }
            }
        }
        .clipped()
        .onAppear {
            model.picking = nil
            let d = UserDefaults.standard
            if d.string(forKey: "cv.openOn") == "last" {
                model.mode = d.bool(forKey: "cv.lastWasFavorites") ? .favorites : .entry
            } else {
                model.mode = .pie
            }
        }
    }

    /// A calculator-style screen (Networking, Number Systems) isn't a real CCategory, but it can still be favorited —
    /// `favKey` is what's stored in `favCategories` for it.
    private struct CalcTool { let id: String; let lines: [String]; let symbol: String; let favKey: String }
    private let calcTools: [CalcTool] = [
        CalcTool(id: "networking-calc", lines: ["Networking"], symbol: "network", favKey: "Networking"),
        CalcTool(id: "number-systems-calc", lines: ["Number", "Systems"], symbol: "number", favKey: "Number Systems"),
    ]
    /// Favorites and Settings as slices on the wheel itself, grouped under their own "Converter" rim label — the only
    /// way to reach them now, the center hub's duplicate shortcut buttons having been removed.
    private static let wheelFavoritesID = "wheel-favorites", wheelSettingsID = "wheel-settings"
    /// Categories clustered by what they're for, each cluster named along the rim.
    private var pieSections: [DialSection] {
        func items(_ ids: [String]) -> [DialItem] {
            // A multi-word name ("Fuel Economy") wraps onto its own line rather than shrinking to a size that can clip near the rim.
            ids.compactMap { id in model.categories.first { $0.id == id } }
                .map { DialItem(id: $0.id, lines: $0.id.split(separator: " ").map(String.init), symbol: $0.symbol, hasFavorite: model.categoryHasFavorite($0.id)) }
        }
        func calc(_ id: String) -> DialItem {
            let t = calcTools.first { $0.id == id }!
            return DialItem(id: t.id, lines: t.lines, symbol: t.symbol, hasFavorite: model.categoryHasFavorite(t.favKey))
        }
        return [
            DialSection(name: "Everyday", items: items(["Length", "Weight", "Volume", "Area", "Temperature", "Fuel Economy", "Currency", "Shoe Size"])),
            DialSection(name: "Converter", items: [
                DialItem(id: Self.wheelFavoritesID, lines: ["Favorites"], symbol: "star.fill"),
                DialItem(id: Self.wheelSettingsID, lines: ["Settings"], symbol: "gearshape")]),
            DialSection(name: "Time & Motion", items: items(["Time", "Speed", "Angle", "Acceleration", "Angular Velocity"])),
            DialSection(name: "Science & Engineering", items: items(["Force", "Torque", "Density", "Pressure", "Illuminance", "Energy", "Power", "Flow Rate", "Viscosity"])),
            DialSection(name: "Electrical", items: items(["Resistance", "Capacitance", "Current", "Voltage", "Frequency", "Battery Energy"])),
            DialSection(name: "Digital & Network", items: items(["Data", "Data Rate", "Network Latency", "Video Storage Rate"]) + [calc("networking-calc"), calc("number-systems-calc")]),
            DialSection(name: "Media", items: items(["Print Resolution", "Focal Length"])),
        ]
    }
    /// Opens whatever slice id was tapped, on either the main dial or the Favorites dial: a real category, or one of the
    /// calculator tools (matched by its dial id on the main dial, or by its favKey when it's a synthesized Favorites tile).
    private func openTile(_ id: String) {
        model.picking = nil
        if id == Self.wheelFavoritesID { model.mode = .favorites; return }
        if id == Self.wheelSettingsID { hideAndShowSettings(); return }
        if let t = calcTools.first(where: { $0.id == id || $0.favKey == id }) {
            switch t.favKey {
            case "Networking": model.mode = .networkCalc
            case "Number Systems": model.mode = .numberSystems
            default: break
            }
            return
        }
        model.select(category: id)
    }
    private var favoriteCategoryItems: [DialItem] {
        let cats = model.categories.filter { model.categoryHasFavorite($0.id) }
            .map { DialItem(id: $0.id, lines: $0.id.split(separator: " ").map(String.init), symbol: $0.symbol, hasFavorite: true) }
        let calcKeys = Array(Set(calcTools.map { $0.favKey })).sorted { $0 < $1 }
        let calcs = calcKeys.filter { model.categoryHasFavorite($0) }.compactMap { key in
            calcTools.first { $0.favKey == key }.map { DialItem(id: $0.favKey, lines: $0.lines, symbol: $0.symbol, hasFavorite: true) }
        }
        return cats + calcs
    }
    /// Fewer rings where the shape gives lots of angular room (a half-circle edge), more where it's tight (a corner or the
    /// full circle in Settings) — packs more categories into one screen at the cost of a bit less room per slice.
    private func rings(for geo: FGeo) -> Int { geo.full ? 4 : geo.isCorner ? 4 : 3 }

    /// The gear, plus one labeled companion button (Favorites on the main dial, All Categories on the Favorites screen),
    /// sit together in the dial's own hub — its dark center circle, nudged into the visible bulge so it can't land right
    /// on the screen edge — then clamped as a last safety net. That position is inside the dial's own dead zone (its
    /// `inner` radius), where the dial itself never recognizes a slice, so a tap here can't ever also select a category.
    private func hub(_ geo: FGeo, leading: (symbol: String, title: String, help: String, action: () -> Void)) -> some View {
        // The hub is a small dark circle (radius ≈ 0.2×geo.radius, drawn by RingDial, centered on the anchor). The two
        // buttons stack vertically inside it and are nudged off the anchor just enough to clear the screen edge on an
        // edge/corner placement — so the true budget for the buttons' own size is what's left of the hub after that nudge,
        // not the hub's full radius. Sized (both font and box) to actually fit that budget at this zone's current size.
        let hubRadius = geo.radius * 0.2
        // On an edge (top/bottom/left/right), `facing` points straight into the visible half-circle, so a small nudge
        // is enough to clear the screen edge. On a corner, `facing` points diagonally out along the bisector — the same
        // small nudge left the buttons sitting almost exactly on the corner itself, and then the asymmetric clamp below
        // (a wide horizontal margin, a much shorter vertical one) pulled them further right than down, reading as
        // "stuck to the top" instead of centered along that diagonal, out toward the middle of the visible slice.
        let offset = geo.radius * (geo.isCorner ? 0.15 : 0.02)
        // A corner only has a quarter-circle of room around the hub (an edge has a half-circle), so it needs a tighter budget.
        let budget = max(18, (hubRadius - offset) * (geo.isCorner ? 0.62 : 1))
        let fontSize = fittedHubFontSize(["Favorites", "All Categories", "Settings"], widthBudget: budget * 2 - 20, heightBudget: budget * 2)
        let stackHeight = 2 * (fontSize + 10) + 2
        let raw = geo.point(offset, geo.facing)
        // The horizontal safety margin still needs the full button-width budget (so a wide label can't clip a side edge),
        // but the vertical one only needs half the stack's own height. On a corner, though, using two different margins
        // pulls the clamped point off the diagonal `offset` placed it on — using the larger of the two for both axes
        // there keeps it centered on that diagonal instead of skewing toward whichever axis has the tighter margin.
        let marginX: CGFloat = budget + 6, marginY: CGFloat = stackHeight / 2 + 6
        let (mX, mY) = geo.isCorner ? (max(marginX, marginY), max(marginX, marginY)) : (marginX, marginY)
        let p = CGPoint(x: min(max(raw.x, mX), geo.size.width - mX), y: min(max(raw.y, mY), geo.size.height - mY))
        return VStack(spacing: 2) {
            hubButton(leading.symbol, leading.title, leading.help, fontSize, action: leading.action)
            hubButton("gearshape", "Settings", "Converter settings", fontSize) { hideAndShowSettings() }
        }
        .position(p)
    }
    private func hubButton(_ symbol: String, _ title: String, _ help: String, _ fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: fontSize, weight: .semibold))
                Text(title).font(.system(size: fontSize, weight: .semibold)).lineLimit(1).fixedSize()
            }.foregroundStyle(.white).padding(.horizontal, fontSize * 0.55).frame(height: fontSize + 10)
            .background(Capsule().fill(Color.black.opacity(0.6)))
        }.buttonStyle(.plain).help(help)
            .simultaneousGesture(TapGesture().onEnded(action))
    }
    /// The largest size (down to a legible floor) at which every one of these labels fits `widthBudget`, and the whole
    /// two-button stack fits `heightBudget`.
    private func fittedHubFontSize(_ labels: [String], widthBudget: CGFloat, heightBudget: CGFloat) -> CGFloat {
        var size: CGFloat = 11
        while size > 6 {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let widest = labels.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width + size * 1.1 }.max() ?? 0
            let totalHeight = 2 * (size + 10) + 2
            if widest <= widthBudget, totalHeight <= heightBudget { break }
            size -= 0.5
        }
        return size
    }
}

// MARK: - Header (back button, search, favorite star, settings)

/// A genuine `View` struct, not a computed property inlined into `Panel`'s own body — a computed property returning
/// `some View` renders visually fine but its Buttons stopped registering clicks entirely (confirmed by direct testing:
/// identical Button+Capsule content one row down, inside a real `View` struct, worked on every coordinate tried; this
/// exact content, inlined via a computed property, worked on none). Giving it its own real type fixed it.
private struct HeaderBar: View {
    @ObservedObject var model: Conv
    @Environment(\.converterScale) private var scale

    private var calcInfo: (symbol: String, title: String)? {
        switch model.mode {
        case .networkCalc: return ("network", "Networking")
        case .numberSystems: return ("number", "Number Systems")
        default: return nil
        }
    }
    private var calcFavKey: String? {
        switch model.mode {
        case .networkCalc: return "Networking"; case .numberSystems: return "Number Systems"
        default: return nil
        }
    }
    var body: some View {
        let oneStepBack = model.picking != nil || model.mode == .search
        let goBack = {
            if model.mode == .search { model.mode = model.searchReturnMode }
            else if model.picking != nil { model.picking = nil; model.query = "" }
            else { model.mode = .pie }
        }
        let openSearch = { model.searchReturnMode = model.mode; model.picking = nil; model.searchQuery = ""; model.mode = .search }
        let openSettings = { hideAndShowSettings() }
        // Below a certain rendered size, SwiftUI/AppKit stops reliably hit-testing a Button at all — confirmed directly:
        // identical content and position registered zero clicks across an exhaustive sweep at an ~11pt font (11 * a 0.36
        // zone scale ≈ 4pt), but worked immediately once the font was left at its unscaled, full size. The header clamps
        // to never shrink below its own 1× reference size, even when the rest of the panel scales down further.
        let hs = max(scale, 1.0)
        return HStack(spacing: 6 * hs) {
            Button(action: goBack) {
                HStack(spacing: 5 * hs) {
                    Image(systemName: "chevron.left").font(.system(size: 11 * hs, weight: .bold))
                    // Text intentionally dropped here (chevron + category icon only): at hs's floor, this label demanded
                    // more width than some real zone sizes have, silently truncating to "An…" and pushing the buttons
                    // after it out of position — this row is never allowed to overflow, so nothing here can ever be wider
                    // than its own fixed icon content, regardless of category name length or how small the zone is.
                    if oneStepBack { Text("Back").font(.system(size: 14 * hs, weight: .semibold)) }
                    else if let calc = calcInfo { Image(systemName: calc.symbol).font(.system(size: 13 * hs)) }
                    else { Image(systemName: model.current.symbol).font(.system(size: 13 * hs)) }
                }.padding(.horizontal, 10 * hs).padding(.vertical, 5 * hs).background(Capsule().fill(Color.primary.opacity(0.13)))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(oneStepBack ? "Back to the converter" : "Back to the categories").cursorPointer()
            Spacer()
            if !oneStepBack && calcInfo == nil {
                Button { model.togglePair() } label: {
                    Image(systemName: model.pairIsFav ? "star.fill" : "star").font(.system(size: 14 * hs))
                        .foregroundStyle(model.pairIsFav ? converterGold : .secondary).frame(width: 30 * hs, height: 28 * hs)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(model.pairIsFav ? "Remove this pair from Favorites" : "Save this pair to Favorites").cursorPointer()
            }
            // Search (every category and unit, not just this screen's) makes sense from a calculator tool too, not just
            // a plain category converter — it was previously hidden there, leaving those headers visibly one button short.
            if !oneStepBack {
                Button(action: openSearch) { Image(systemName: "magnifyingglass").font(.system(size: 14 * hs, weight: .semibold)).frame(width: 30 * hs, height: 28 * hs).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Search every unit").cursorPointer()
            }
            if !oneStepBack, let key = calcFavKey {
                Button { model.toggleCategoryFav(key) } label: {
                    Image(systemName: model.categoryHasFavorite(key) ? "star.fill" : "star").font(.system(size: 14 * hs))
                        .foregroundStyle(model.categoryHasFavorite(key) ? converterGold : .secondary).frame(width: 30 * hs, height: 28 * hs)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(model.categoryHasFavorite(key) ? "Remove from Favorites" : "Add to Favorites").cursorPointer()
            }
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 14 * hs)).frame(width: 30 * hs, height: 28 * hs).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Converter settings: all units, favorites, and quick convert").cursorPointer()
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 30 * hs)
    }
}

/// A pointing-hand cursor while hovering, so it's visually obvious a small icon-only control is clickable — SwiftUI on
/// macOS doesn't do this automatically for a custom `Button` the way it does for text links or native controls.
extension View {
    func cursorPointer() -> some View {
        onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - The converter screen (laid out at its true final size — see `converterScale`)

private struct Panel: View {
    @ObservedObject var model: Conv
    @Environment(\.converterScale) private var scale
    var body: some View {
        // A ZStack overlay, not a VStack sibling: a ScrollView-based calculator screen (NetworkCalcView etc.) doesn't
        // shrink to its own content the way a plain VStack does — it always claims the *entire* space VStack offers it,
        // and something about that negotiation between a fixed-height HeaderBar and a space-claiming ScrollView sibling
        // was pushing HeaderBar down by however much shorter that screen's content was, even with explicit top-alignment
        // on every frame in the chain. Overlaying HeaderBar instead makes its position structurally independent of
        // whatever the content below is doing — it can't be pushed around by a sibling's layout behavior it isn't one.
        ZStack(alignment: .top) {
            Group {
                if model.mode == .search { SearchList(model: model) }
                else if model.mode == .networkCalc { NetworkCalcView() }
                else if model.mode == .numberSystems { NumberSystemsView() }
                else if model.picking != nil { UnitList(model: model) }
                else { converter }
            }
            .padding(.top, 30 * max(scale, 1.0) + 10 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            HeaderBar(model: model)
        }
        .padding(.horizontal, 12 * scale).padding(.top, 14 * scale).padding(.bottom, 10 * scale)
    }

    private var converter: some View {
        VStack(spacing: 6 * scale) {
            SideBox(model: model, title: "From", unit: model.from, which: .from)
            HStack {
                Spacer()
                Button { model.swap() } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 14 * scale, weight: .semibold)).frame(width: 40 * scale, height: 28 * scale).background(Capsule().fill(Color.primary.opacity(0.1))) }
                    .buttonStyle(.plain).help("Swap the two units")
                Spacer()
            }
            SideBox(model: model, title: "To", unit: model.to, which: .to)
            Spacer(minLength: 0)
            footer
        }
    }
    private var footer: some View {
        Group {
            if model.current.id == "Currency" {
                if model.rates.perUSD.isEmpty { Text(model.rates.failed ? "Can't load exchange rates (offline?)" : "Loading exchange rates…") }
                else { Text("Indicative rates" + (model.rates.updated.map { ", updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "") + ". Not a bank quote.") }
            } else { Text(" ") }
        }.font(.system(size: 9 * scale)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }
}

// MARK: - Unit list (favorites first, then A–Z)

private struct UnitList: View {
    @ObservedObject var model: Conv
    @Environment(\.converterScale) private var scale
    var body: some View {
        let list = model.pickList
        VStack(spacing: 6 * scale) {
            HStack {
                Text(model.picking == .from ? "From" : "To").font(.system(size: 14 * scale, weight: .bold))
                Text("· \(model.current.id)").font(.system(size: 14 * scale)).foregroundStyle(.secondary)
                Spacer()
            }
            searchField(model.query, "Type to search", scale)
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2 * scale) {
                    if !list.favorites.isEmpty {
                        header("Favorites", scale)
                        ForEach(list.favorites) { row($0) }
                        header(model.current.id == "Currency" ? "All currencies" : "All units", scale)
                    }
                    ForEach(list.others) { row($0) }
                    if list.favorites.isEmpty && list.others.isEmpty { Text("Nothing matches.").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.top, 20 * scale) }
                }
            }
        }
    }
    private func row(_ u: CUnit) -> some View {
        let selected = u.id == (model.picking == .from ? model.fromID : model.toID)
        return HStack(spacing: 6 * scale) {
            Button { model.toggleFav(u.id) } label: {
                Image(systemName: model.isFav(u.id) ? "star.fill" : "star").font(.system(size: 14 * scale)).foregroundStyle(model.isFav(u.id) ? converterGold : .secondary).frame(width: 26 * scale, height: 32 * scale)
            }.buttonStyle(.plain).help(model.isFav(u.id) ? "Remove from favorites" : "Keep at the top of the list")
            Button {
                if let side = model.picking { model.set(side, u.id) }
                model.picking = nil; model.query = ""
            } label: {
                HStack(spacing: 7 * scale) {
                    if let f = u.flag { Text(f).font(.system(size: 19 * scale)) }
                    Text(u.name).font(.system(size: 14 * scale, weight: selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text(u.symbol).font(.system(size: 13 * scale)).foregroundStyle(.secondary)
                    if selected { Image(systemName: "checkmark").font(.system(size: 11 * scale, weight: .bold)) }
                }.frame(height: 32 * scale).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(.horizontal, 6 * scale).background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
    }
}

/// The From or To box: either can be typed into. Tap anywhere on the number to make it active (a highlighted border and a
/// blinking cursor show where typing goes) — the whole row responds to hover too, not just the thin line of digits, so it's
/// clear before you even click that the box is what you'd tap.
private struct SideBox: View {
    @ObservedObject var model: Conv
    let title: String
    let unit: CUnit?
    let which: Conv.Side
    @State private var hoveringAmount = false
    @Environment(\.converterScale) private var scale

    var body: some View {
        let active = model.active == which
        return VStack(alignment: .leading, spacing: 4 * scale) {
            Text(title.uppercased()).font(.system(size: 10 * scale, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            HStack(spacing: 6 * scale) {
                Button { model.focus(which) } label: {
                    HStack(spacing: 6 * scale) {
                        // Was 34/40 — that made each card taller than the 320×270 design budget `bestFit` sizes the
                        // whole panel around, so the card's own bottom corners could run past the visible circle.
                        Text(model.text(which)).font(.system(size: 28 * scale, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
                        if active { BlinkingCursor(scale: scale) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 34 * scale).contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hoveringAmount && !active ? 0.08 : 0)))
                }.buttonStyle(.plain).onHover { hoveringAmount = $0 }
                if !active {
                    Button { model.copy(which) } label: { Image(systemName: model.copied && model.copiedSide == which ? "checkmark" : "doc.on.doc").font(.system(size: 12 * scale)).foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Copy")
                }
            }
            Button { model.picking = which; model.query = "" } label: {
                HStack(spacing: 7 * scale) {
                    if let f = unit?.flag { Text(f).font(.system(size: 19 * scale)) }
                    Text(unit?.name ?? "Loading…").font(.system(size: 15 * scale, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(unit?.symbol ?? "").font(.system(size: 13 * scale)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                }.padding(.horizontal, 10 * scale).frame(height: 30 * scale)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.1))).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(8 * scale)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.primary.opacity(active ? 0.1 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(active ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 2))
    }
}

/// A thin blinking bar after the active number, so it's obvious where typing goes.
private struct BlinkingCursor: View {
    let scale: CGFloat
    @State private var on = true
    var body: some View {
        Rectangle().fill(Color.accentColor).frame(width: 2 * scale, height: 26 * scale).opacity(on ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) { on.toggle() } }
    }
}

private func header(_ s: String, _ scale: CGFloat) -> some View {
    Text(s.uppercased()).font(.system(size: 10 * scale, weight: .bold)).tracking(1).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6 * scale).padding(.bottom, 1 * scale)
}
private func searchField(_ text: String, _ placeholder: String, _ scale: CGFloat) -> some View {
    HStack(spacing: 6 * scale) {
        Image(systemName: "magnifyingglass").font(.system(size: 12 * scale)).foregroundStyle(.secondary)
        Text(text.isEmpty ? placeholder : text).font(.system(size: 14 * scale)).foregroundStyle(text.isEmpty ? .secondary : .primary)
        Spacer()
    }.padding(.horizontal, 10 * scale).frame(height: 30 * scale).background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.12)))
}

// MARK: - Search across every unit

private struct SearchList: View {
    @ObservedObject var model: Conv
    @Environment(\.converterScale) private var scale
    var body: some View {
        let results = model.searchResults, cats = model.categoryMatches
        VStack(spacing: 6 * scale) {
            searchField(model.searchQuery, "Type a category, unit or currency", scale)
            if results.isEmpty && cats.isEmpty {
                Text(model.searchQuery.isEmpty ? "Search by category (\"temperature\") or unit (\"gallon\", \"psi\", \"peso\")." : "Nothing matches.").font(.system(size: 12 * scale)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 24 * scale)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2 * scale) {
                        if !cats.isEmpty {
                            header("Categories", scale)
                            ForEach(cats) { c in
                                Button { model.select(category: c.id) } label: {
                                    HStack(spacing: 7 * scale) {
                                        Image(systemName: c.symbol).font(.system(size: 13 * scale)).frame(width: 18 * scale)
                                        Text(c.id).font(.system(size: 14 * scale, weight: .medium))
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                                    }.padding(.horizontal, 8 * scale).frame(height: 32 * scale).contentShape(Rectangle())
                                }.buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.09)))
                            }
                            if !results.isEmpty { header("Units", scale) }
                        }
                        ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                            Button { model.pick(searchResult: r) } label: {
                                HStack(spacing: 7 * scale) {
                                    if let f = r.unit.flag { Text(f).font(.system(size: 19 * scale)) }
                                    Text(r.unit.name).font(.system(size: 14 * scale)).lineLimit(1).minimumScaleFactor(0.75)
                                    Spacer(minLength: 4)
                                    Text(r.category).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                                    Text(r.unit.symbol).font(.system(size: 13 * scale, weight: .medium)).frame(width: 46 * scale, alignment: .trailing)
                                }.padding(.horizontal, 8 * scale).frame(height: 32 * scale).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }
        }
    }
}
