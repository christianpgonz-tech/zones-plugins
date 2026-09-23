import AppKit
import SwiftUI

/// Networking math that doesn't fit a simple From/To pair: parsing an address, a CIDR block, a channel table, or a
/// two-number estimate. Kept separate from the Catalog engine, which only ever does one proportional conversion at a time.
enum NetMath {
    static func octets(_ ip: String) -> [UInt8]? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts { guard let n = UInt8(p) else { return nil }; out.append(n) }
        return out
    }
    static func binary(_ ip: String) -> String? {
        guard let o = octets(ip) else { return nil }
        return o.map { String(String($0, radix: 2)).leftPadded(8) }.joined(separator: ".")
    }
    static func hex(_ ip: String) -> String? {
        guard let o = octets(ip) else { return nil }
        return "0x" + o.map { String(format: "%02X", $0) }.joined()
    }

    static func subnetMask(_ prefix: Int) -> String? {
        guard (0...32).contains(prefix) else { return nil }
        let bits: UInt32 = prefix == 0 ? 0 : (prefix == 32 ? .max : (~UInt32(0)) << (32 - prefix))
        return [(bits >> 24) & 0xFF, (bits >> 16) & 0xFF, (bits >> 8) & 0xFF, bits & 0xFF].map { String($0) }.joined(separator: ".")
    }
    static func hostCount(_ prefix: Int) -> Int? {
        guard (0...32).contains(prefix) else { return nil }
        if prefix >= 31 { return prefix == 32 ? 1 : 2 }        // /31 point-to-point (2 usable), /32 a single host
        return Int(pow(2.0, Double(32 - prefix))) - 2
    }

    /// Channel → center frequency (MHz). 2.4GHz channels are evenly spaced; 5GHz channels are not, so this is a lookup.
    static let wifi24: [(channel: Int, mhz: Double)] = (1...14).map { c in (c, c == 14 ? 2484 : 2412 + Double(c - 1) * 5) }
    static let wifi5: [(channel: Int, mhz: Double)] = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165]
        .map { ($0, 5000 + Double($0) * 5) }

    /// How long a transfer takes at a given (constant) speed. Returns seconds.
    static func transferSeconds(bytes: Double, bitsPerSecond: Double) -> Double? {
        guard bitsPerSecond > 0 else { return nil }
        return bytes * 8 / bitsPerSecond
    }
    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return String(format: "%.1f sec", seconds) }
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %dm %ds", h, m, sec) }
        return String(format: "%dm %ds", m, sec)
    }
}
private extension String { func leftPadded(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self } }

// MARK: - View

/// Four small networking tools in one screen, reached from the Digital & Network group's own slice (it's math, not a
/// simple two-unit conversion, so it doesn't use the usual From/To picker).
struct NetworkCalcView: View {
    @State private var ip = "192.168.1.1"
    @State private var prefix = "24"
    @State private var band5 = false
    @State private var channel = 6.0
    @State private var sizeValue = "1"
    @State private var sizeUnit = "GB"
    @State private var speedValue = "100"
    @State private var speedUnit = "Mbps"

    private let sizeUnits: [(String, Double)] = [("MB", 1_000_000), ("GB", 1_000_000_000), ("TB", 1_000_000_000_000)]
    private let speedUnits: [(String, Double)] = [("Kbps", 1_000), ("Mbps", 1_000_000), ("Gbps", 1_000_000_000)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                tool("IP Address", "network") {
                    TextField("192.168.1.1", text: $ip).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                    if let bin = NetMath.binary(ip), let hex = NetMath.hex(ip) {
                        row("Binary", bin); row("Hex", hex)
                    } else { Text("Type a full IPv4 address, like 192.168.1.1.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                tool("CIDR Block", "square.grid.3x3") {
                    HStack(spacing: 4) {
                        Text("/").font(.system(size: 13, weight: .semibold))
                        TextField("24", text: $prefix).textFieldStyle(.roundedBorder).frame(width: 50)
                    }
                    if let p = Int(prefix), let mask = NetMath.subnetMask(p), let hosts = NetMath.hostCount(p) {
                        row("Subnet mask", mask); row("Usable hosts", "\(hosts)")
                    } else { Text("Type a prefix from 0–32.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                tool("Wi-Fi Channel", "wifi") {
                    Picker("", selection: $band5) { Text("2.4 GHz").tag(false); Text("5 GHz").tag(true) }.pickerStyle(.segmented).labelsHidden()
                        .onChange(of: band5) { channel = Double((band5 ? NetMath.wifi5.first?.channel : NetMath.wifi24.first?.channel) ?? 1) }
                    let table = band5 ? NetMath.wifi5 : NetMath.wifi24
                    Picker("Channel", selection: $channel) { ForEach(table, id: \.channel) { Text("Ch \($0.channel)").tag(Double($0.channel)) } }
                    if let hit = table.first(where: { Double($0.channel) == channel }) { row("Center frequency", "\(Int(hit.mhz)) MHz") }
                }
                tool("Transfer Time", "clock.arrow.circlepath") {
                    HStack {
                        TextField("Size", text: $sizeValue).textFieldStyle(.roundedBorder)
                        Picker("", selection: $sizeUnit) { ForEach(sizeUnits, id: \.0) { Text($0.0).tag($0.0) } }.labelsHidden().frame(width: 70)
                    }
                    HStack {
                        TextField("Speed", text: $speedValue).textFieldStyle(.roundedBorder)
                        Picker("", selection: $speedUnit) { ForEach(speedUnits, id: \.0) { Text($0.0).tag($0.0) } }.labelsHidden().frame(width: 70)
                    }
                    if let sv = Double(sizeValue), let spv = Double(speedValue), spv > 0,
                       let bytes = sizeUnits.first(where: { $0.0 == sizeUnit })?.1, let bps = speedUnits.first(where: { $0.0 == speedUnit })?.1,
                       let secs = NetMath.transferSeconds(bytes: sv * bytes, bitsPerSecond: spv * bps) {
                        row("Time", NetMath.formatDuration(secs))
                    } else { Text("Enter a file size and a connection speed.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Text("Wi-Fi channel positions and subnet math are standard references; transfer time assumes a steady, uninterrupted connection.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
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
