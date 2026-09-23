import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(CalculatorZone)
public final class CalculatorZone: NSObject {
    @objc public var zoneIdentifier: String { "calculator" }
    @objc public var zoneTitle: String { "Calculator" }
    @objc public var zoneSymbol: String { "plusminus.circle" }
    @objc public var zonePreferredWidth: NSNumber { 220 }
    @objc public var zonePreferredHeight: NSNumber { 280 }
    @objc public var zoneAllowedPlacements: [String] { ["top", "bottom", "topLeft", "topRight", "bottomLeft", "bottomRight"] }
    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let calc = Calc()
        let view = CalcHostingView(rootView: CalculatorView(calc: calc))
        view.calc = calc
        // Don't let the SwiftUI content push its own size onto the zone; the zone decides the size.
        view.sizingOptions = []
        return view
    }
}

/// Listens for the keyboard while the zone's panel is the key window. Clicking anywhere in the zone
/// makes it key, so a click is all it takes before typing.
final class CalcHostingView: NSHostingView<CalculatorView> {
    var calc: Calc?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if event.type == .leftMouseDown { if !window.isKeyWindow { window.makeKey() }; return event }
            guard window.isKeyWindow, let key = Self.key(for: event) else { return event }
            self.calc?.press(key)
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private static func key(for event: NSEvent) -> String? {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return nil }
        switch event.keyCode {
        case 36, 76: return "="
        case 51, 117: return "⌫"
        default: break
        }
        guard let c = event.charactersIgnoringModifiers?.lowercased(), c.count == 1 else { return nil }
        switch c {
        case "0"..."9", ".": return c
        case ",": return "."
        case "+": return "+"
        case "-": return "−"
        case "*", "x": return "×"
        case "/": return "÷"
        case "=": return "="
        case "%": return "%"
        case "c": return "C"
        default: return nil
        }
    }
}

final class Calc: ObservableObject {
    @Published var display = "0"
    private var stored: Double?
    private var op: String?
    private var fresh = true
    private var value: Double { Double(display) ?? 0 }
    private func show(_ v: Double) { display = v == v.rounded() && abs(v) < 1e12 ? String(Int(v)) : String(format: "%.8g", v) }
    private func apply() {
        guard let a = stored, let op else { return }
        let b = value
        switch op { case "+": show(a + b); case "−": show(a - b); case "×": show(a * b); default: b == 0 ? (display = "Error") : show(a / b) }
    }
    func press(_ key: String) {
        if display == "Error" && key != "C" { display = "0"; fresh = true }
        switch key {
        case "C": display = "0"; stored = nil; op = nil; fresh = true
        case "⌫": if !fresh { display.removeLast(); if display.isEmpty || display == "-" { display = "0"; fresh = true } }
        case "±": show(-value)
        case "%": show(value / 100)
        case "+", "−", "×", "÷": if !fresh { apply() }; stored = value; op = key; fresh = true
        case "=": apply(); stored = nil; op = nil; fresh = true
        case ".": if fresh { display = "0."; fresh = false } else if !display.contains(".") { display += "." }
        default: if fresh || display == "0" { display = key; fresh = false } else { display += key }
        }
    }
}

struct CalculatorView: View {
    @ObservedObject var calc: Calc
    private let rows = [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "="]]
    var body: some View {
        VStack(spacing: 5) {
            Text(calc.display).font(.system(size: 24, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .trailing).padding(.horizontal, 8)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Button { calc.press(key) } label: {
                            Text(key).font(.body).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(["÷", "×", "−", "+", "="].contains(key) ? 0.22 : 0.1)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}
