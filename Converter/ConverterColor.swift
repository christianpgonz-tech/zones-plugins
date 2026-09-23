import AppKit
import SwiftUI

/// RGB ↔ hex ↔ HSL — not a proportional conversion (three numbers move together), so it's a calculator screen.
enum ColorMath {
    static func hex(r: Int, g: Int, b: Int) -> String { String(format: "#%02X%02X%02X", r, g, b) }
    static func rgb(fromHex hex: String) -> (Int, Int, Int)? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
    }
    /// r,g,b in 0–255; returns h in 0–360, s and l in 0–100.
    static func hsl(r: Int, g: Int, b: Int) -> (Double, Double, Double) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), d = mx - mn
        let l = (mx + mn) / 2
        guard d > 0 else { return (0, 0, l * 100) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
        case gf: h = (bf - rf) / d + 2
        default: h = (rf - gf) / d + 4
        }
        return (h * 60, s * 100, l * 100)
    }
}

struct ColorCalcView: View {
    @State private var r: Double = 59
    @State private var g: Double = 130
    @State private var b: Double = 246
    @State private var hexText = "3B82F6"

    private var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                tool("Color", "eyedropper") {
                    HStack(spacing: 4) {
                        Text("#").font(.system(size: 13, weight: .semibold))
                        TextField("3B82F6", text: $hexText).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                    }
                    ColorPicker("Pick from screen or palette…", selection: Binding(get: { color }, set: setFrom), supportsOpacity: false)
                        .font(.system(size: 12))
                        .help("Opens the system color picker — click the eyedropper icon inside it to sample any pixel on your screen")
                    RoundedRectangle(cornerRadius: 8).fill(color).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                    slider("R", $r); slider("G", $g); slider("B", $b)
                    row("Hex", ColorMath.hex(r: Int(r), g: Int(g), b: Int(b)))
                    row("RGB", "\(Int(r)), \(Int(g)), \(Int(b))")
                    let (h, s, l) = ColorMath.hsl(r: Int(r), g: Int(g), b: Int(b))
                    row("HSL", "\(Int(h.rounded()))°, \(Int(s.rounded()))%, \(Int(l.rounded()))%")
                }
                Text("Drag the sliders, type exact numbers, or use the color picker's eyedropper to sample any pixel on your screen.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
        }
        .onChange(of: r) { _, new in r = clamp(new); syncHex() }
        .onChange(of: g) { _, new in g = clamp(new); syncHex() }
        .onChange(of: b) { _, new in b = clamp(new); syncHex() }
        .onChange(of: hexText) { _, new in if let (nr, ng, nb) = ColorMath.rgb(fromHex: new) { r = Double(nr); g = Double(ng); b = Double(nb) } }
    }
    private func clamp(_ v: Double) -> Double { min(255, max(0, v)) }
    private func setFrom(_ c: Color) {
        guard let comps = NSColor(c).usingColorSpace(.deviceRGB) else { return }
        r = (comps.redComponent * 255).rounded(); g = (comps.greenComponent * 255).rounded(); b = (comps.blueComponent * 255).rounded()
    }
    private func syncHex() { hexText = ColorMath.hex(r: Int(r), g: Int(g), b: Int(b)) }
    private func slider(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).frame(width: 14)
            RGBTrack(value: value)
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 44)
        }
    }
    private func tool<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .bold))
            content()
        }.padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Text(value).font(.system(size: 12, weight: .semibold).monospaced()) }
    }
}

/// A hand-drawn 0–255 track: the stock macOS `Slider` draws its unfilled remainder as a thin line under the thicker
/// filled portion, which read as a stray extra line running under each R/G/B row — this draws one continuous,
/// uniform-thickness track instead, with no such seam.
private struct RGBTrack: View {
    @Binding var value: Double
    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 16
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fraction = value / 255
            let thumbX = fraction * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: trackHeight)
                Capsule().fill(Color.accentColor).frame(width: max(thumbSize / 2, thumbX), height: trackHeight)
                Circle().fill(Color.white).frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .offset(x: min(max(thumbX, thumbSize / 2), w - thumbSize / 2) - thumbSize / 2)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(255, max(0, (g.location.x / w) * 255)).rounded()
            })
        }
        .frame(height: thumbSize)
    }
}
