import AppKit
import SwiftUI

/// Number-base and character-code math — not a proportional conversion, so it's a calculator screen like Networking.
enum NumMath {
    static func parse(_ text: String, radix: Int) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Int(t, radix: radix)
    }
    static func binary(_ n: Int) -> String { n < 0 ? "-" + String(-n, radix: 2) : String(n, radix: 2) }
    static func hex(_ n: Int) -> String { (n < 0 ? "-" : "") + String(abs(n), radix: 16).uppercased() }
    static func octal(_ n: Int) -> String { (n < 0 ? "-" : "") + String(abs(n), radix: 8) }
}

struct NumberSystemsView: View {
    @State private var value = "255"
    @State private var base = 10

    @State private var charInput = "A"
    private let bases: [(String, Int)] = [("Binary", 2), ("Octal", 8), ("Decimal", 10), ("Hex", 16)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                tool("Number Base", "number") {
                    HStack {
                        TextField("Value", text: $value).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                        Picker("", selection: $base) { ForEach(bases, id: \.1) { Text($0.0).tag($0.1) } }.labelsHidden().frame(width: 90)
                    }
                    if let n = NumMath.parse(value, radix: base) {
                        row("Binary", NumMath.binary(n)); row("Octal", NumMath.octal(n)); row("Decimal", "\(n)"); row("Hex", "0x" + NumMath.hex(n))
                    } else { Text("Enter a value valid in the chosen base.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                tool("ASCII / Unicode", "character") {
                    TextField("A single character or a decimal code point", text: $charInput).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                    if let code = codePoint(charInput) {
                        let scalar = UnicodeScalar(code)
                        row("Character", scalar.map { String(Character($0)) } ?? "—")
                        row("Decimal", "\(code)"); row("Hex", "0x" + NumMath.hex(code)); row("Binary", NumMath.binary(code))
                    } else { Text("Type one character, or its decimal code point (like 65 for \"A\").").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Text("Character codes cover the full Unicode range, not just 7-bit ASCII.").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
        }
    }
    private func codePoint(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count == 1, let scalar = t.unicodeScalars.first { return Int(scalar.value) }
        return Int(t)
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
