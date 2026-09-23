import AppKit
import SwiftUI

/// The gear menu: every unit by category (star the ones you want at the top), your favorite pairs, and how the zone opens.
final class ConverterSettingsController {
    static let shared = ConverterSettingsController()
    private(set) var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Converter Settings"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 480)
            w.contentView = NSHostingView(rootView: ConverterSettingsView())
            w.center()
            window = w
        }
        Rates.shared.load()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ConverterSettingsView: View {
    @ObservedObject var model = Conv.shared
    @AppStorage("cv.openOn") private var openOn = "pie"
    @State private var selected = "Length"
    @State private var pairFrom = ""
    @State private var pairTo = ""
    @State private var quickText = ""
    @State private var quickError = false

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { Optional(selected) }, set: { if let v = $0 { selected = v; pairFrom = ""; pairTo = "" } })) {
                Section("Categories") {
                    ForEach(model.categories) { c in
                        HStack {
                            Label(c.id, systemImage: c.symbol)
                            Spacer()
                            Button { model.toggleCategoryFav(c.id) } label: {
                                Image(systemName: model.categoryHasFavorite(c.id) ? "star.fill" : "star")
                                    .foregroundStyle(model.categoryHasFavorite(c.id) ? converterGold : .secondary)
                            }.buttonStyle(.plain).help(model.categoryHasFavorite(c.id) ? "Remove from Favorites" : "Add to Favorites")
                        }.tag(c.id)
                    }
                }
                Section("Favorite pairs") { Label("\(model.favPairs.count) saved", systemImage: "star").foregroundStyle(.secondary) }
            }.listStyle(.sidebar).frame(width: 190)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let cat = model.categories.first { $0.id == selected } ?? Catalog.length
                    HStack {
                        Text(cat.id).font(.title2.weight(.semibold))
                        Button { model.toggleCategoryFav(cat.id) } label: {
                            Image(systemName: model.categoryHasFavorite(cat.id) ? "star.fill" : "star")
                                .foregroundStyle(model.categoryHasFavorite(cat.id) ? converterGold : .secondary)
                        }.buttonStyle(.plain).help(model.categoryHasFavorite(cat.id) ? "Remove this category from Favorites" : "Add this category to Favorites")
                    }
                    Text("Star the category above to add it to the Favorites screen. Tap a unit's star to keep it at the top of this list.").font(.callout).foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        ForEach(cat.units.sorted { model.isFav($0.id, in: cat.id) != model.isFav($1.id, in: cat.id) ? model.isFav($0.id, in: cat.id) : $0.name < $1.name }) { u in
                            HStack(spacing: 10) {
                                Button { model.toggleFav(u.id, in: cat.id) } label: {
                                    Image(systemName: model.isFav(u.id, in: cat.id) ? "star.fill" : "star").foregroundStyle(model.isFav(u.id, in: cat.id) ? converterGold : .secondary).frame(width: 24)
                                }.buttonStyle(.plain)
                                if let f = u.flag { Text(f).font(.title3) }
                                Text(u.name)
                                Spacer()
                                Text(u.symbol).foregroundStyle(.secondary)
                            }.padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                        }
                    }
                    Divider()
                    Text("Favorite pairs").font(.headline)
                    Text("A pair is a From and a To unit, like USD → CLP. Your pairs appear as slices on the Favorites dial.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("From", selection: $pairFrom) { ForEach(cat.units) { Text(($0.flag.map { $0 + " " } ?? "") + $0.name).tag($0.id) } }
                        Picker("To", selection: $pairTo) { ForEach(cat.units) { Text(($0.flag.map { $0 + " " } ?? "") + $0.name).tag($0.id) } }
                        Button("Add pair") {
                            let a = pairFrom.isEmpty ? (cat.units.first?.id ?? "") : pairFrom, b = pairTo.isEmpty ? (cat.units.dropFirst().first?.id ?? "") : pairTo
                            model.addPair(cat.id, a, b)
                        }
                    }
                    if model.favPairs.isEmpty { Text("No pairs yet.").foregroundStyle(.secondary) }
                    ForEach(model.favPairs, id: \.self) { key in
                        if let l = model.label(pair: key) {
                            HStack {
                                Text(l.category).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                Text("\(l.from)  →  \(l.to)")
                                Spacer()
                                Button { model.favPairs.removeAll { $0 == key } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                            }.padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                        }
                    }
                    Divider()
                    Text("Quick convert").font(.headline)
                    Text("Type something like \"5 km to mi\" or \"100 usd to clp\" and press Return.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("5 km to mi", text: $quickText, onCommit: applyQuick)
                        Button("Convert", action: applyQuick).disabled(quickText.isEmpty)
                    }
                    if quickError { Text("Didn't understand that — try \"amount unit to unit\".").font(.caption).foregroundStyle(.red) }
                    Divider()
                    Text("When the zone opens").font(.headline)
                    Picker("", selection: $openOn) {
                        Text("On the last converter I used").tag("last")
                        Text("On the category dial").tag("pie")
                    }.pickerStyle(.radioGroup).labelsHidden()
                    Divider()
                    Text("Currency rates are indicative daily rates from open.er-api.com, loaded online and saved for offline use. They are not a bank quote.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { selected = model.category }
    }
    private func applyQuick() {
        guard let r = Convert.parse(quickText, categories: model.categories, preferred: model.category) else { quickError = true; return }
        model.setPair(category: r.category, from: r.from, to: r.to)
        model.select(category: r.category)
        model.active = .from
        model.fromText = Convert.format(r.amount).replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
        model.recompute()
        selected = r.category; quickText = ""; quickError = false
    }
}
