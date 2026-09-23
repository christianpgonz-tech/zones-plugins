import AppKit
import SwiftUI

/// The full flat table in its own floating window: leave it open, move it, resize it. The dial keeps working next to it.
final class TableWindowController {
    static let shared = TableWindowController()
    private var window: NSWindow?
    private let model = TableModel(placement: "top")

    func show() {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Periodic Table"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.hidesOnDeactivate = false
            w.isFloatingPanel = true
            w.minSize = NSSize(width: 800, height: 460)
            w.contentView = NSHostingView(rootView: TableWindowView(model: model))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // Remembers where the user last put it and how big they made it.
            if !w.setFrameUsingName("PeriodicTableWindow") { w.center() }
            w.setFrameAutosaveName("PeriodicTableWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TableWindowView: View {
    @ObservedObject var model: TableModel
    var body: some View {
        let matches = Set(model.results.map(\.number))
        let searching = !model.query.isEmpty
        VStack(spacing: 10) {
            toolbar
            TileGrid(cells: allElements.map { .init(element: $0, col: Double($0.x - 1), row: $0.y <= 7 ? Double($0.y - 1) : Double($0.y) - 1.6) },
                     cols: 18, rows: 9.4,
                     dim: { e in (searching && !matches.contains(e.number)) || (model.familyFilter.map { $0 != e.family } ?? false) },
                     model: model)
            status
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if model.selected != nil {
                ZStack {
                    Color.black.opacity(0.35).onTapGesture { model.selected = nil }
                    GeometryReader { proxy in
                        let k = min(proxy.size.width * 0.78 / 320, proxy.size.height * 0.86 / 232)
                        DetailCard(model: model).frame(width: 320, height: 232).scaleEffect(k)
                            .frame(width: 320 * k, height: 232 * k)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15)))
                            .shadow(radius: 14)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search by name, symbol or number", text: $model.query).textFieldStyle(.plain)
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 8).frame(width: 300, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                Spacer(minLength: 0)
                Text("Temperature").font(.caption).foregroundStyle(.secondary)
                Button(model.unit.rawValue) { model.unit = model.unit.next }.buttonStyle(.plain).font(.callout.weight(.semibold)).help("Switch temperature unit")
            }
            HStack(spacing: 6) {
                chip("All", color: .secondary, on: model.familyFilter == nil) { model.familyFilter = nil }
                ForEach(Family.allCases, id: \.self) { family in
                    chip(family.short, color: family.dialColor, on: model.familyFilter == family) { model.familyFilter = model.familyFilter == family ? nil : family }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func chip(_ title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(on ? .semibold : .regular)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(on ? 0.16 : 0.06)))
        }.buttonStyle(.plain)
    }
    private var status: some View {
        HStack {
            if let e = model.hovered {
                Text("\(e.number) · \(e.name) (\(e.symbol)) · \(e.mass.map { String(format: "%.3f", $0) } ?? "") · \(e.family.title)").font(.callout)
            } else { Text("Hover an element for a quick look, click it for the full card.").font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Text("Data: Periodic-Table-JSON · Wikipedia").font(.caption2).foregroundStyle(.secondary)
        }.frame(height: 18)
    }
}

extension Family {
    var short: String {
        switch self {
        case .alkali: "Alkali"
        case .alkalineEarth: "Alk. earth"
        case .transition: "Transition"
        case .postTransition: "Post-trans."
        case .metalloid: "Metalloid"
        case .nonmetal: "Nonmetal"
        case .noble: "Noble gas"
        case .lanthanide: "Lanthanide"
        case .actinide: "Actinide"
        }
    }
}
