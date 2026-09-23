import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(PeriodicTableZone)
public final class PeriodicTableZone: NSObject {
    @objc public var zoneIdentifier: String { "periodic-table" }
    @objc public var zoneTitle: String { "Periodic Table" }
    @objc public var zoneSymbol: String { "atom" }
    @objc public var zonePreferredWidth: NSNumber { 320 }
    @objc public var zonePreferredHeight: NSNumber { 224 }
    @objc public var zoneAllowedPlacements: [String] { ["top", "bottom", "left", "right", "topLeft", "topRight", "bottomLeft", "bottomRight"] }
    /// Draws across the whole curved shape (the dial), starts bigger than usual, and can be sized both ways.
    @objc public var zoneUsesFullShape: NSNumber { true }
    @objc public var zoneDefaultScale: NSNumber { 1.35 }
    @objc public var zoneMinimumScale: NSNumber { 0.8 }
    @objc public var zoneMaximumScale: NSNumber { 2.0 }
    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let model = TableModel(placement: (context["placement"] as? String) ?? "top")
        let view = TableHostingView(rootView: PeriodicTableView(model: model))
        view.model = model
        view.sizingOptions = []
        return view
    }
}

// MARK: - Data

struct Element: Decodable, Identifiable, Hashable {
    let number: Int
    let symbol: String
    let name: String
    let mass: Double?
    let category: String
    let x: Int
    let y: Int
    let phase: String?
    let melt: Double?          // kelvin
    let boil: Double?          // kelvin
    let density: Double?       // g/cm³
    let electronegativity: Double?
    let config: String?
    let shells: [Int]?
    let discoveredBy: String?
    var id: Int { number }
    /// The dataset files Nihonium under transition metals; chemists expect it beside Fl, Mc and Lv.
    var family: Family { (113...116).contains(number) ? .postTransition : Family(category) }
    /// Elements past 103 have only predicted properties.
    var measured: Bool { number <= 103 }
}

enum Family: CaseIterable {
    case alkali, alkalineEarth, transition, postTransition, metalloid, nonmetal, noble, lanthanide, actinide
    init(_ category: String) {
        let c = category.lowercased()
        if c.contains("noble gas") { self = .noble }
        else if c.contains("alkaline earth") { self = .alkalineEarth }
        else if c.contains("alkali") { self = .alkali }
        else if c.contains("lanthanide") { self = .lanthanide }
        else if c.contains("actinide") { self = .actinide }
        else if c.contains("post-transition") { self = .postTransition }
        else if c.contains("transition") { self = .transition }
        else if c.contains("metalloid") { self = .metalloid }
        else { self = .nonmetal }
    }
    var title: String {
        switch self {
        case .alkali: "Alkali metal"
        case .alkalineEarth: "Alkaline earth metal"
        case .transition: "Transition metal"
        case .postTransition: "Post-transition metal"
        case .metalloid: "Metalloid"
        case .nonmetal: "Nonmetal"
        case .noble: "Noble gas"
        case .lanthanide: "Lanthanide"
        case .actinide: "Actinide"
        }
    }
    var color: Color {
        switch self {
        case .alkali: Color(hue: 0.99, saturation: 0.65, brightness: 0.85)
        case .alkalineEarth: Color(hue: 0.07, saturation: 0.70, brightness: 0.88)
        case .transition: Color(hue: 0.58, saturation: 0.55, brightness: 0.85)
        case .postTransition: Color(hue: 0.48, saturation: 0.55, brightness: 0.72)
        case .metalloid: Color(hue: 0.36, saturation: 0.50, brightness: 0.70)
        case .nonmetal: Color(hue: 0.15, saturation: 0.60, brightness: 0.86)
        case .noble: Color(hue: 0.76, saturation: 0.45, brightness: 0.88)
        case .lanthanide: Color(hue: 0.90, saturation: 0.45, brightness: 0.88)
        case .actinide: Color(hue: 0.83, saturation: 0.55, brightness: 0.72)
        }
    }
}

enum Temperature: String, CaseIterable {
    case celsius = "°C", fahrenheit = "°F", kelvin = "K"
    var next: Temperature { self == .celsius ? .fahrenheit : self == .fahrenheit ? .kelvin : .celsius }
    func format(kelvin k: Double?) -> String {
        guard let k else { return "—" }
        switch self {
        case .kelvin: return "\(Int(k.rounded())) K"
        case .celsius: return "\(Int((k - 273.15).rounded())) °C"
        case .fahrenheit: return "\(Int(((k - 273.15) * 9 / 5 + 32).rounded())) °F"
        }
    }
}

let allElements: [Element] = {
    let bundle = Bundle(for: PeriodicTableZone.self)
    guard let url = bundle.url(forResource: "elements", withExtension: "json"), let data = try? Data(contentsOf: url),
          let list = try? JSONDecoder().decode([Element].self, from: data) else { return [] }
    return list.sorted { $0.number < $1.number }
}()

// MARK: - Model

final class TableModel: ObservableObject {
    @Published var query = ""
    @Published var selected: Element?
    @Published var hovered: Element?
    @Published var unit: Temperature = .celsius
    let placement: String
    /// Used by the table window: dims every element outside the chosen family.
    @Published var familyFilter: Family?
    @Published var rotation: Double = 0
    @Published var pointer: CGPoint?
    @Published var hoveredDial: Element?
    @Published var dragging = false
    @Published var hasRotated = false
    var omega: Double = 0
    var goal: Double?
    private var ticker: Timer?
    init(placement: String) {
        self.placement = placement
        rotation = DialGeometry.startRotation(placement: placement)
    }
    func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }
    private func tick() {
        var moving = false
        if let goal {
            let d = goal - rotation
            if abs(d) < 0.002 { rotation = goal; self.goal = nil } else { rotation += d * 0.16; moving = true }
        } else if !dragging, abs(omega) > 0.01 {
            rotation += omega / 60; omega *= 0.94; moving = true
        }
        if !moving { ticker?.invalidate(); ticker = nil }
    }
    func spin(by delta: Double) { goal = (goal ?? rotation) + delta; omega = 0; hasRotated = true; startTicker() }
    func spinToShow(_ element: Element) {
        let target = DialGeometry.centerAngle(placement: placement) - (Double(element.x) - 0.5) * DialGeometry.step
        goal = rotation + DialGeometry.wrap(target - rotation); omega = 0; startTicker()
    }

    var results: [Element] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if let n = Int(q) { return allElements.filter { String($0.number).hasPrefix(q) || $0.number == n } }
        let exact = allElements.filter { $0.symbol.lowercased() == q }
        let starts = allElements.filter { $0.name.lowercased().hasPrefix(q) && !exact.contains($0) }
        let contains = allElements.filter { $0.name.lowercased().contains(q) && !exact.contains($0) && !starts.contains($0) }
        let symbols = allElements.filter { $0.symbol.lowercased().hasPrefix(q) && !exact.contains($0) && !starts.contains($0) && !contains.contains($0) }
        return exact + starts + contains + symbols
    }
    func open(_ element: Element) { selected = element; query = "" }
    func step(_ direction: Int) {
        guard let current = selected, let next = allElements.first(where: { $0.number == current.number + direction }) else { return }
        selected = next
    }
    func handle(_ key: String) {
        switch key {
        case "←": selected != nil ? step(-1) : spin(by: -DialGeometry.step * 2)
        case "→": selected != nil ? step(1) : spin(by: DialGeometry.step * 2)
        case "⌫":
            if !query.isEmpty { query.removeLast(); if let first = results.first { spinToShow(first) } }
            else if selected != nil { selected = nil }
        case "↩": if let first = results.first { open(first) }
        default:
            selected = nil
            if query.count < 14 { query += key }
            if let first = results.first { spinToShow(first) }
        }
    }
}

/// Listens for the keyboard while the zone's panel is the key window. Clicking the zone makes it key,
/// so a click and then typing is all it takes: letters, digits, arrows, Delete, Return.
final class TableHostingView: NSHostingView<PeriodicTableView> {
    var model: TableModel?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if event.type == .scrollWheel {
                if let model = self.model, model.selected == nil {
                    model.goal = nil; model.omega = 0; model.hasRotated = true
                    model.rotation += Double(event.scrollingDeltaY + event.scrollingDeltaX) * 0.005
                }
                return event
            }
            if event.type == .leftMouseDown { if !window.isKeyWindow { window.makeKey() }; return event }
            guard window.isKeyWindow, let key = Self.key(for: event) else { return event }
            self.model?.handle(key)
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private static func key(for event: NSEvent) -> String? {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return nil }
        switch event.keyCode {
        case 123: return "←"
        case 124: return "→"
        case 51, 117: return "⌫"
        case 36, 76: return "↩"
        default: break
        }
        guard let c = event.charactersIgnoringModifiers?.lowercased(), c.count == 1, let scalar = c.unicodeScalars.first else { return nil }
        return CharacterSet.alphanumerics.contains(scalar) ? c : nil
    }
}

// MARK: - Views

/// The dial fills the whole shape; clicking an element swaps it for the detail card, scaled to the
/// largest rectangle that fits inside the shape.
struct PeriodicTableView: View {
    @ObservedObject var model: TableModel
    private let design = CGSize(width: 320, height: 232)
    var body: some View {
        GeometryReader { proxy in
            let geo = DialGeometry(placement: model.placement, size: proxy.size)
            ZStack(alignment: .topLeading) {
                if model.selected == nil {
                    DialView(model: model, geo: geo)
                } else {
                    Color.clear.contentShape(Rectangle()).onTapGesture { model.selected = nil }
                    let fit = geo.bestFit(design: design)
                    DetailCard(model: model)
                        .frame(width: design.width, height: design.height)
                        .scaleEffect(fit.scale)
                        .frame(width: design.width * fit.scale, height: design.height * fit.scale)
                        .position(fit.center)
                }
            }
        }.clipped()
    }
}

/// The click view: a Back / unit bar above the element's full card.
struct DetailCard: View {
    @ObservedObject var model: TableModel
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { model.selected = nil } label: { Label("Back", systemImage: "chevron.left").font(.caption.weight(.semibold)) }.buttonStyle(.plain)
                Spacer()
                Button(model.unit.rawValue) { model.unit = model.unit.next }.buttonStyle(.plain).font(.caption.weight(.semibold)).help("Switch temperature unit")
            }
            .frame(height: 22).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            if let element = model.selected { DetailView(element: element, model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.padding(.horizontal, 8).padding(.vertical, 6)
    }
}

/// Places elements in a grid of fractional columns/rows, sized to fill whatever space they're given.
struct TileGrid: View {
    struct Cell { let element: Element; let col: Double; let row: Double }
    let cells: [Cell]
    let cols: Double
    let rows: Double
    var dim: (Element) -> Bool = { _ in false }
    @ObservedObject var model: TableModel
    var body: some View {
        GeometryReader { proxy in
            let tw = proxy.size.width / cols, th = proxy.size.height / rows
            ZStack(alignment: .topLeading) {
                ForEach(cells, id: \.element.number) { cell in
                    let hovered = model.hovered == cell.element
                    // Tap and hover attach to the tile's own square, before it is positioned: a positioned
                    // view otherwise claims the whole grid, and only the last tile would ever respond.
                    Tile(element: cell.element, width: tw - 3, height: th - 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: hovered ? 2.5 : 0))
                        .scaleEffect(hovered ? 1.2 : 1)
                        .shadow(color: .black.opacity(hovered ? 0.45 : 0), radius: 9, y: 3)
                        .opacity(dim(cell.element) ? 0.2 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { model.open(cell.element) }
                        .onHover { inside in
                            if inside { model.hovered = cell.element } else if model.hovered == cell.element { model.hovered = nil }
                        }
                        .zIndex(hovered ? 1 : 0)
                        .position(x: (cell.col + 0.5) * tw, y: (cell.row + 0.5) * th)
                }
            }
        }
    }
}

/// One element tile: number, symbol and (when it fits) the name, with fonts that grow with the tile.
struct Tile: View {
    let element: Element
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        let symbolSize = min(width * 0.38, height * 0.36, 22)
        let numberSize = max(7, min(11, height * 0.16))
        let nameSize = max(6.5, min(10, height * 0.15))
        let nameFits = width * 0.94 >= CGFloat(element.name.count) * nameSize * 0.54 && height >= 34
        ZStack {
            RoundedRectangle(cornerRadius: min(5, width / 5)).fill(element.family.dialColor)
            if width >= 22 && height >= 22 {
                VStack(spacing: 0) {
                    if height >= 30 { Text("\(element.number)").font(.system(size: numberSize).monospacedDigit()).opacity(0.75) }
                    Text(element.symbol).font(.system(size: symbolSize, weight: .bold))
                    if nameFits { Text(element.name).font(.system(size: nameSize)).opacity(0.85).lineLimit(1) }
                }
            }
        }.frame(width: width, height: height).foregroundStyle(Color.black.opacity(0.85)).contentShape(Rectangle())
    }
}

struct DetailView: View {
    let element: Element
    @ObservedObject var model: TableModel
    var body: some View {
        let color = element.family.color
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Text("\(element.number)").font(.system(size: 12).monospacedDigit())
                    Text(element.symbol).font(.system(size: 36, weight: .bold))
                    Text(element.mass.map { String(format: "%.3f", $0) } ?? "").font(.system(size: 10).monospacedDigit())
                }
                .frame(width: 72, height: 76).foregroundStyle(Color.black.opacity(0.85))
                .background(RoundedRectangle(cornerRadius: 8).fill(element.family.dialColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name).font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(familyLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(element.family.dialColor)
                    if element.measured, let phase = element.phase { Text("\(phase) at room temp").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                    else { Text("Predicted properties").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                    if let by = element.discoveredBy, !by.isEmpty { Text("Discovered by \(by)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                if let shells = element.shells { BohrModel(shells: shells, color: color).frame(width: 84, height: 84) }
            }
            if element.measured {
                HStack(spacing: 0) {
                    fact("Melts", model.unit.format(kelvin: element.melt))
                    fact("Boils", model.unit.format(kelvin: element.boil))
                    fact("Density", element.density.map { String(format: "%g g/cm³", $0) } ?? "—")
                    fact("Electroneg.", element.electronegativity.map { String(format: "%.2f", $0) } ?? "—")
                }
            }
            if let config = element.config {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Electron configuration").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(config).font(.system(size: 14, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button { model.step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(element.number == 1)
                Spacer()
                Text("Data: Periodic-Table-JSON · Wikipedia").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button { model.step(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(element.number == 118)
            }.font(.caption)
        }
        .contentShape(Rectangle())
    }
    private var familyLabel: String {
        element.category.lowercased().hasPrefix("unknown") ? "Probably \(element.family.title.lowercased())" : element.family.title
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A simple Bohr model drawn from the element's electron shells: a nucleus and one slowly turning ring per shell.
struct BohrModel: View {
    let shells: [Int]
    let color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = min(size.width, size.height) / 2 - 3
                let t = context.date.timeIntervalSinceReferenceDate
                let count = max(shells.count, 1)
                g.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(color))
                for (i, n) in shells.enumerated() {
                    let r = 8 + (maxR - 8) * Double(i + 1) / Double(count)
                    g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.primary.opacity(0.18)), lineWidth: 0.6)
                    let speed = 0.5 / Double(i + 1)
                    for k in 0..<n {
                        let a = Double(k) / Double(n) * .pi * 2 + t * speed * (i % 2 == 0 ? 1 : -1)
                        let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                        g.fill(Path(ellipseIn: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)), with: .color(.primary.opacity(0.85)))
                    }
                }
            }
        }
    }
}
