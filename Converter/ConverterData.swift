import AppKit
import SwiftUI

// MARK: - Units

/// One unit. Everything converts through the category's base unit: base = value * factor + offset.
struct CUnit: Identifiable, Hashable {
    let id: String              // unique inside its category ("km", "USD")
    let name: String            // "Kilometer"
    let symbol: String          // "km"
    var factor: Double
    var offset: Double = 0
    var flag: String? = nil     // currencies only
    var aliases: [String] = []
    /// Fuel economy only: "miles per gallon" and "liters per 100km" are reciprocal, not proportional.
    /// When true, base = factor / value (instead of base = value * factor + offset).
    var reciprocal: Bool = false
    /// dBm only: a decibel unit isn't proportional either, it's logarithmic. When set, base = logRef * 10^(value / logScale).
    var logScale: Double? = nil
    var logRef: Double = 1
}

struct CCategory: Identifiable, Hashable {
    let id: String              // "Length"
    let symbol: String          // SF symbol for the chip
    var units: [CUnit]
}

enum Catalog {
    private static func u(_ id: String, _ name: String, _ symbol: String, _ factor: Double, _ offset: Double = 0, _ aliases: [String] = [], reciprocal: Bool = false) -> CUnit {
        CUnit(id: id, name: name, symbol: symbol, factor: factor, offset: offset, aliases: aliases, reciprocal: reciprocal)
    }
    private static func ulog(_ id: String, _ name: String, _ symbol: String, scale: Double, ref: Double, _ aliases: [String] = []) -> CUnit {
        CUnit(id: id, name: name, symbol: symbol, factor: 1, aliases: aliases, logScale: scale, logRef: ref)
    }

    static let length = CCategory(id: "Length", symbol: "ruler", units: [
        u("mm", "Millimeter", "mm", 0.001, 0, ["millimetre"]), u("cm", "Centimeter", "cm", 0.01, 0, ["centimetre"]), u("m", "Meter", "m", 1, 0, ["metre"]),
        u("km", "Kilometer", "km", 1000, 0, ["kilometre"]), u("um", "Micrometer", "µm", 1e-6, 0, ["micron", "micrometre"]),
        u("in", "Inch", "in", 0.0254, 0, ["inches", "\""]), u("ft", "Foot", "ft", 0.3048, 0, ["feet", "'"]), u("yd", "Yard", "yd", 0.9144),
        u("mi", "Mile", "mi", 1609.344, 0, ["miles"]), u("nmi", "Nautical mile", "nmi", 1852)])
    static let temperature = CCategory(id: "Temperature", symbol: "thermometer.medium", units: [
        u("C", "Celsius", "°C", 1, 0, ["c", "centigrade"]), u("F", "Fahrenheit", "°F", 5.0 / 9.0, -160.0 / 9.0, ["f"]),
        u("K", "Kelvin", "K", 1, -273.15, ["k"]), u("R", "Rankine", "°R", 5.0 / 9.0, -273.15)])
    static let area = CCategory(id: "Area", symbol: "square.dashed", units: [
        u("mm2", "Square millimeter", "mm²", 1e-6), u("cm2", "Square centimeter", "cm²", 1e-4), u("m2", "Square meter", "m²", 1),
        u("ha", "Hectare", "ha", 10_000, 0, ["hectares"]), u("km2", "Square kilometer", "km²", 1e6),
        u("in2", "Square inch", "in²", 0.00064516), u("ft2", "Square foot", "ft²", 0.09290304, 0, ["sqft"]), u("yd2", "Square yard", "yd²", 0.83612736),
        u("ac", "Acre", "ac", 4046.8564224, 0, ["acres"]), u("mi2", "Square mile", "mi²", 2_589_988.110336)])
    static let volume = CCategory(id: "Volume", symbol: "cube", units: [
        u("mL", "Milliliter", "mL", 0.001, 0, ["ml", "millilitre"]), u("L", "Liter", "L", 1, 0, ["l", "litre", "liters"]), u("m3", "Cubic meter", "m³", 1000),
        u("tsp", "Teaspoon (US)", "tsp", 0.00492892159375), u("tbsp", "Tablespoon (US)", "tbsp", 0.01478676478125),
        u("floz", "Fluid ounce (US)", "fl oz", 0.0295735295625), u("cup", "Cup (US)", "cup", 0.2365882365, 0, ["cups"]),
        u("pt", "Pint (US)", "pt", 0.473176473), u("qt", "Quart (US)", "qt", 0.946352946), u("gal", "Gallon (US)", "gal", 3.785411784, 0, ["gallons"]),
        u("galuk", "Gallon (UK)", "gal UK", 4.54609), u("flozuk", "Fluid ounce (UK)", "fl oz UK", 0.0284130625),
        u("in3", "Cubic inch", "in³", 0.016387064), u("ft3", "Cubic foot", "ft³", 28.316846592)])
    static let weight = CCategory(id: "Weight", symbol: "scalemass", units: [
        u("mg", "Milligram", "mg", 1e-6), u("g", "Gram", "g", 0.001, 0, ["grams"]), u("kg", "Kilogram", "kg", 1, 0, ["kilo", "kilos"]),
        u("t", "Metric ton", "t", 1000, 0, ["tonne", "tonnes"]), u("oz", "Ounce", "oz", 0.028349523125, 0, ["ounces"]),
        u("lb", "Pound", "lb", 0.45359237, 0, ["lbs", "pounds"]), u("st", "Stone", "st", 6.35029318),
        u("tonus", "Ton (US)", "ton", 907.18474), u("tonuk", "Ton (UK)", "long ton", 1016.0469088)])
    static let time = CCategory(id: "Time", symbol: "clock", units: [
        u("ms", "Millisecond", "ms", 0.001), u("s", "Second", "s", 1, 0, ["sec", "seconds"]), u("min", "Minute", "min", 60, 0, ["minutes"]),
        u("h", "Hour", "h", 3600, 0, ["hr", "hours"]), u("d", "Day", "d", 86_400, 0, ["days"]), u("wk", "Week", "wk", 604_800, 0, ["weeks"]),
        u("mo", "Month", "mo", 2_629_800, 0, ["months"]), u("yr", "Year", "yr", 31_557_600, 0, ["years"])])
    static let pressure = CCategory(id: "Pressure", symbol: "gauge.with.dots.needle.bottom.50percent", units: [
        u("Pa", "Pascal", "Pa", 1, 0, ["pa"]), u("kPa", "Kilopascal", "kPa", 1000, 0, ["kpa"]), u("MPa", "Megapascal", "MPa", 1e6),
        u("bar", "Bar", "bar", 1e5), u("mbar", "Millibar", "mbar", 100), u("atm", "Atmosphere", "atm", 101_325),
        u("psi", "Pound per square inch", "psi", 6894.757293168), u("mmHg", "Millimeter of mercury", "mmHg", 133.322387415),
        u("inHg", "Inch of mercury", "inHg", 3386.389), u("torr", "Torr", "Torr", 133.3223684211)])
    static let speed = CCategory(id: "Speed", symbol: "speedometer", units: [
        u("mps", "Meter per second", "m/s", 1), u("kph", "Kilometer per hour", "km/h", 1 / 3.6, 0, ["kmh", "kph"]),
        u("mph", "Mile per hour", "mph", 0.44704), u("kn", "Knot", "kn", 1852.0 / 3600.0, 0, ["knots"]),
        u("fps", "Foot per second", "ft/s", 0.3048), u("mach", "Mach", "Mach", 340.29)])
    static let energy = CCategory(id: "Energy", symbol: "bolt", units: [
        u("J", "Joule", "J", 1, 0, ["j", "joules"]), u("kJ", "Kilojoule", "kJ", 1000), u("cal", "Calorie", "cal", 4.184),
        u("kcal", "Kilocalorie", "kcal", 4184, 0, ["calories", "food calorie"]), u("Wh", "Watt-hour", "Wh", 3600, 0, ["wh"]),
        u("kWh", "Kilowatt-hour", "kWh", 3_600_000, 0, ["kwh"]), u("BTU", "British thermal unit", "BTU", 1055.05585262, 0, ["btu"]),
        u("ftlbf", "Foot-pound", "ft·lbf", 1.3558179483314)])

    static let force = CCategory(id: "Force", symbol: "arrow.up.forward", units: [
        u("N", "Newton", "N", 1, 0, ["newton", "newtons"]), u("kN", "Kilonewton", "kN", 1000), u("lbf", "Pound-force", "lbf", 4.4482216152605, 0, ["pound force"]),
        u("kgf", "Kilogram-force", "kgf", 9.80665), u("dyn", "Dyne", "dyn", 1e-5)])
    static let acceleration = CCategory(id: "Acceleration", symbol: "arrow.up.right.circle", units: [
        u("mps2", "Meter per second²", "m/s²", 1), u("g", "Standard gravity", "g", 9.80665, 0, ["gravity"]),
        u("fps2", "Foot per second²", "ft/s²", 0.3048), u("gal", "Gal", "Gal", 0.01)])
    static let torque = CCategory(id: "Torque", symbol: "arrow.triangle.2.circlepath", units: [
        u("Nm", "Newton-meter", "N·m", 1, 0, ["nm"]), u("kNm", "Kilonewton-meter", "kN·m", 1000),
        u("ftlbf", "Foot-pound", "ft·lbf", 1.3558179483314), u("inlbf", "Inch-pound", "in·lbf", 0.1129848290276), u("kgfm", "Kilogram-force meter", "kgf·m", 9.80665)])
    static let density = CCategory(id: "Density", symbol: "circle.grid.3x3.fill", units: [
        u("kgm3", "Kilogram per m³", "kg/m³", 1), u("gcm3", "Gram per cm³", "g/cm³", 1000, 0, ["g/ml"]), u("kgL", "Kilogram per liter", "kg/L", 1000),
        u("lbft3", "Pound per ft³", "lb/ft³", 16.018463374), u("lbgal", "Pound per gallon (US)", "lb/gal", 119.826427317)])
    static let illuminance = CCategory(id: "Illuminance", symbol: "sun.max.fill", units: [
        u("lux", "Lux", "lx", 1, 0, ["lx"]), u("fc", "Foot-candle", "fc", 10.76391, 0, ["footcandle"]), u("ph", "Phot", "ph", 10_000)])
    static let power = CCategory(id: "Power", symbol: "bolt.horizontal.circle", units: [
        u("W", "Watt", "W", 1, 0, ["watt", "watts"]), u("mW", "Milliwatt", "mW", 0.001), u("kW", "Kilowatt", "kW", 1000), u("MW", "Megawatt", "MW", 1e6),
        u("hp", "Horsepower", "hp", 745.6998715822702), u("ps", "Metric horsepower", "PS", 735.49875), u("BTUh", "BTU per hour", "BTU/h", 0.29307107017),
        ulog("dBm", "dBm (referenced to 1 mW)", "dBm", scale: 10, ref: 0.001, ["dbm", "decibel-milliwatt"])])
    static let angle = CCategory(id: "Angle", symbol: "angle", units: [
        u("deg", "Degree", "°", 1, 0, ["degrees"]), u("rad", "Radian", "rad", 57.29577951308232, 0, ["radians"]), u("grad", "Gradian", "grad", 0.9),
        u("turn", "Full turn", "turn", 360, 0, ["revolution", "rev"]), u("arcmin", "Arcminute", "′", 1.0 / 60), u("arcsec", "Arcsecond", "″", 1.0 / 3600)])
    static let dataStorage = CCategory(id: "Data", symbol: "externaldrive", units: [
        u("bit", "Bit", "bit", 1.0 / 8), u("byte", "Byte", "B", 1, 0, ["bytes"]), u("KB", "Kilobyte", "KB", 1000), u("MB", "Megabyte", "MB", 1_000_000),
        u("GB", "Gigabyte", "GB", 1_000_000_000, 0, ["gb", "gig"]), u("TB", "Terabyte", "TB", 1e12), u("KiB", "Kibibyte", "KiB", 1024),
        u("MiB", "Mebibyte", "MiB", 1_048_576), u("GiB", "Gibibyte", "GiB", 1_073_741_824), u("TiB", "Tebibyte", "TiB", 1_099_511_627_776)])
    /// Miles per gallon and liters-per-100km are reciprocal, not proportional (a bigger mpg means a smaller L/100km), so these units carry `reciprocal: true`.
    static let fuelEconomy = CCategory(id: "Fuel Economy", symbol: "fuelpump", units: [
        u("L100km", "Liter per 100 km", "L/100km", 1), u("mpgus", "Mile per gallon (US)", "mpg (US)", 235.214583, reciprocal: true),
        u("mpguk", "Mile per gallon (UK)", "mpg (UK)", 282.480936, reciprocal: true), u("kml", "Kilometer per liter", "km/L", 100, reciprocal: true)])

    static let resistance = CCategory(id: "Resistance", symbol: "waveform.path.ecg", units: [
        u("ohm", "Ohm", "Ω", 1, 0, ["ohms"]), u("kohm", "Kilohm", "kΩ", 1000), u("Mohm", "Megohm", "MΩ", 1e6)])
    static let capacitance = CCategory(id: "Capacitance", symbol: "capsule.portrait", units: [
        u("pF", "Picofarad", "pF", 1e-12), u("nF", "Nanofarad", "nF", 1e-9), u("uF", "Microfarad", "µF", 1e-6), u("mF", "Millifarad", "mF", 1e-3), u("F", "Farad", "F", 1)])
    static let current = CCategory(id: "Current", symbol: "bolt.circle", units: [
        u("uA", "Microamp", "µA", 1e-6), u("mA", "Milliamp", "mA", 1e-3), u("A", "Amp", "A", 1, 0, ["amps", "ampere"]), u("kA", "Kiloamp", "kA", 1000)])
    static let voltage = CCategory(id: "Voltage", symbol: "bolt.batteryblock", units: [
        u("mV", "Millivolt", "mV", 1e-3), u("V", "Volt", "V", 1, 0, ["volts"]), u("kV", "Kilovolt", "kV", 1000)])
    /// Radio wavelength and frequency are reciprocal (c = f·λ): base = speed of light / value, same pattern as Fuel Economy.
    static let frequency = CCategory(id: "Frequency", symbol: "waveform", units: [
        u("Hz", "Hertz", "Hz", 1, 0, ["hz"]), u("kHz", "Kilohertz", "kHz", 1000), u("MHz", "Megahertz", "MHz", 1e6), u("GHz", "Gigahertz", "GHz", 1e9),
        u("wavelength_m", "Wavelength (in air)", "λ m", 299_792_458, 0, ["wavelength"], reciprocal: true)])
    static let dataRate = CCategory(id: "Data Rate", symbol: "arrow.up.arrow.down.circle", units: [
        u("bps", "Bit per second", "bps", 0.125), u("Kbps", "Kilobit per second", "Kbps", 125), u("Mbps", "Megabit per second", "Mbps", 125_000),
        u("Gbps", "Gigabit per second", "Gbps", 125_000_000), u("KBps", "Kilobyte per second", "KB/s", 1000), u("MBps", "Megabyte per second", "MB/s", 1_000_000),
        u("GBps", "Gigabyte per second", "GB/s", 1_000_000_000)])
    /// A rough fiber-optic estimate (light travels at about 200,000 km/s through fiber, roughly ⅔ of its speed in a vacuum).
    static let latency = CCategory(id: "Network Latency", symbol: "antenna.radiowaves.left.and.right", units: [
        u("ms", "Millisecond", "ms", 1), u("s", "Second", "s", 1000),
        u("km_fiber", "Kilometer (one-way, fiber)", "km", 0.005, 0, ["kilometer"]), u("mi_fiber", "Mile (one-way, fiber)", "mi", 0.005 * 1.609344, 0, ["mile"])])
    static let flowRate = CCategory(id: "Flow Rate", symbol: "drop", units: [
        u("Lmin", "Liter per minute", "L/min", 1), u("Ls", "Liter per second", "L/s", 60),
        u("gpm", "Gallon per minute (US)", "GPM", 3.785411784), u("m3h", "Cubic meter per hour", "m³/h", 1000.0 / 60),
        u("cfm", "Cubic foot per minute", "CFM", 28.316846592)])
    static let viscosity = CCategory(id: "Viscosity", symbol: "water.waves", units: [
        u("Pas", "Pascal-second", "Pa·s", 1), u("cP", "Centipoise", "cP", 0.001, 0, ["centipoise"])])
    /// A print's pixel count at a given resolution; each "@ dpi" unit is that many pixels per inch (or per 2.54 cm).
    static let printResolution = CCategory(id: "Print Resolution", symbol: "printer", units: [
        u("px", "Pixel", "px", 1, 0, ["pixel", "pixels"]), u("in72", "Inch @ 72 dpi", "in @72", 72), u("in150", "Inch @ 150 dpi", "in @150", 150),
        u("in300", "Inch @ 300 dpi", "in @300", 300), u("in600", "Inch @ 600 dpi", "in @600", 600), u("cm300", "Centimeter @ 300 dpi", "cm @300", 300 / 2.54)])
    /// A lens's actual focal length on a given sensor, compared with the 35mm/full-frame focal length that gives the same
    /// field of view. Base is that 35mm-equivalent value; an "actual mm on X sensor" unit's factor is X's crop multiplier,
    /// since equivalent = actual × crop factor.
    static let focalLength = CCategory(id: "Focal Length", symbol: "camera.aperture", units: [
        u("mm", "35mm / full-frame (mm)", "mm (FF)", 1, 0, ["actual", "full frame"]),
        u("apsc_canon", "Actual mm, APS-C (Canon, 1.6×)", "mm (1.6×)", 1.6), u("apsc", "Actual mm, APS-C (Nikon/Sony, 1.5×)", "mm (1.5×)", 1.5),
        u("mft", "Actual mm, Micro Four Thirds (2×)", "mm (2×)", 2.0), u("1inch", "Actual mm, 1-inch sensor (2.7×)", "mm (2.7×)", 2.7)])

    /// Shoe sizes aren't a physical unit — brands vary — so this is the commonly published approximate guide (a general/men's
    /// scale), the same "offset" trick as Celsius/Fahrenheit, based on US size.
    static let shoeSize = CCategory(id: "Shoe Size", symbol: "shoe", units: [
        u("us", "US", "US", 1, 0, ["american"]), u("eu", "EU", "EU", 1, -33, ["european"]), u("uk", "UK", "UK", 1, 1, ["british"]),
        u("cm", "Foot length (cm)", "cm", 1.5, -31, ["centimeter", "centimetre"])])

    /// The currencies shown (the stronger, most-used ones), with the country whose flag stands for each.
    static let currencyRegions: [(code: String, region: String)] = [
        ("USD", "US"), ("EUR", "EU"), ("GBP", "GB"), ("JPY", "JP"), ("CAD", "CA"), ("AUD", "AU"), ("CHF", "CH"), ("CNY", "CN"),
        ("CLP", "CL"), ("MXN", "MX"), ("BRL", "BR"), ("ARS", "AR"), ("COP", "CO"), ("PEN", "PE"),
        ("INR", "IN"), ("KRW", "KR"), ("SGD", "SG"), ("HKD", "HK"), ("NZD", "NZ"), ("SEK", "SE"), ("NOK", "NO"), ("DKK", "DK"),
        ("PLN", "PL"), ("CZK", "CZ"), ("TRY", "TR"), ("ZAR", "ZA"), ("AED", "AE"), ("SAR", "SA"), ("ILS", "IL"), ("THB", "TH")]

    static func flag(_ region: String) -> String {
        if region == "EU" { return "🇪🇺" }
        return region.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map { String($0) }.joined()
    }

    static let angularVelocity = CCategory(id: "Angular Velocity", symbol: "gauge.with.needle", units: [
        u("rads", "Radian per second", "rad/s", 1), u("degs", "Degree per second", "°/s", 0.017453292519943295),
        u("rpm", "Revolution per minute", "rpm", 0.10471975511965977, 0, ["rpm"]), u("revs", "Revolution per second", "rev/s", 6.283185307179586)])
    /// A battery's mAh rating only means something at a stated voltage (energy = mAh × V ÷ 1000), so each unit here is
    /// "mAh at a common nominal voltage" — the same preset-rate trick as Shoe Size, based on watt-hours.
    static let batteryEnergy = CCategory(id: "Battery Energy", symbol: "battery.100percent", units: [
        u("Wh", "Watt-hour", "Wh", 1, 0, ["wh"]), u("mah37", "mAh @ 3.7V (phone/Li-ion cell)", "mAh @3.7V", 0.0037),
        u("mah5", "mAh @ 5V (USB power bank)", "mAh @5V", 0.005), u("ah12", "Ah @ 12V (car battery)", "Ah @12V", 12)])
    /// A rough storage-per-time estimate from a video's bitrate (storage bytes = bitrate × time ÷ 8), the same kind of
    /// assumed-rate trick as Battery Energy, based on gigabytes per hour of recording.
    static let videoStorageRate = CCategory(id: "Video Storage Rate", symbol: "video", units: [
        u("GBh", "Gigabyte per hour", "GB/hr", 1), u("mbps", "Bitrate (Mbps)", "Mbps", 0.45),
        u("MBmin", "Megabyte per minute", "MB/min", 0.06), u("MBs", "Megabyte per second", "MB/s", 3.6)])

    static let fixed: [CCategory] = [length, temperature, area, volume, weight, time, pressure, speed, energy,
        force, acceleration, torque, density, illuminance, power, angle, dataStorage, fuelEconomy, shoeSize,
        resistance, capacitance, current, voltage, frequency, dataRate, latency, flowRate, viscosity, printResolution, focalLength,
        angularVelocity, batteryEnergy, videoStorageRate]
}

// MARK: - Exchange rates

/// Rates come from open.er-api.com (free, no account), loaded while the zone runs and cached on disk so it still works offline.
/// They are indicative daily rates, not a bank quote.
final class Rates: ObservableObject {
    static let shared = Rates()
    @Published var perUSD: [String: Double] = [:]
    @Published var updated: Date?
    @Published var failed = false
    private let fixture: URL? = ProcessInfo.processInfo.environment["CONVERTER_FIXTURES"].map { URL(fileURLWithPath: $0) }

    static var cacheFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zones/Converter", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("rates.json")
    }

    func load() {
        if let fixture, let data = try? Data(contentsOf: fixture.appendingPathComponent("rates.json")) { parse(data); return }
        if let data = try? Data(contentsOf: Self.cacheFile) { parse(data) }
        let age = updated.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age > 6 * 3600, let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Zones-Converter/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                if let data, (response as? HTTPURLResponse)?.statusCode == 200, self.parse(data) { try? data.write(to: Self.cacheFile); self.failed = false }
                else if self.perUSD.isEmpty { self.failed = true }
            }
        }.resume()
    }

    @discardableResult private func parse(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rates = root["rates"] as? [String: Double], rates["USD"] != nil else { return false }
        perUSD = rates
        if let t = root["time_last_update_unix"] as? Double { updated = Date(timeIntervalSince1970: t) }
        return true
    }

    /// The currency category, or nil until rates are known.
    func category() -> CCategory {
        let units: [CUnit] = Catalog.currencyRegions.compactMap { code, region in
            guard let rate = perUSD[code], rate > 0 else { return nil }
            let name = Locale(identifier: "en_US").localizedString(forCurrencyCode: code) ?? code
            return CUnit(id: code, name: name, symbol: code, factor: 1 / rate, offset: 0, flag: Catalog.flag(region), aliases: [code.lowercased()])
        }
        return CCategory(id: "Currency", symbol: "dollarsign.circle", units: units)
    }
}

// MARK: - Converting and formatting

enum Convert {
    private static func toBase(_ v: Double, _ u: CUnit) -> Double {
        if let ls = u.logScale { return u.logRef * pow(10, v / ls) }
        return u.reciprocal ? u.factor / v : v * u.factor + u.offset
    }
    private static func fromBase(_ base: Double, _ u: CUnit) -> Double {
        if let ls = u.logScale { return ls * log10(base / u.logRef) }
        return u.reciprocal ? u.factor / base : (base - u.offset) / u.factor
    }
    static func value(_ v: Double, from: CUnit, to: CUnit) -> Double { fromBase(toBase(v, from), to) }

    static func format(_ v: Double, currency: Bool = false) -> String {
        guard v.isFinite else { return "—" }
        if v == 0 { return "0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        if abs(v) >= 1e13 || abs(v) < 1e-7 { return String(format: "%.6g", v) }
        if currency { f.minimumFractionDigits = 2; f.maximumFractionDigits = 2 }
        else { f.usesSignificantDigits = true; f.maximumSignificantDigits = 9; f.minimumSignificantDigits = 1 }
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// Reads "5 km to mi", "72 f in c", "100 usd to clp" (the first unit found, looking in `preferred` first).
    static func parse(_ text: String, categories: [CCategory], preferred: String) -> (category: String, from: String, to: String, amount: Double)? {
        let pattern = #"^\s*(-?[0-9][0-9.,]*)\s*(.+?)\s+(?:to|in|into|->|>|=)\s+(.+?)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text), let r3 = Range(m.range(at: 3), in: text),
              let amount = Double(text[r1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let ordered = categories.sorted { ($0.id == preferred ? 0 : 1) < ($1.id == preferred ? 0 : 1) }
        func key(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "") }
        func find(_ s: String) -> [(String, CUnit)] {
            let k = key(s)
            return ordered.flatMap { c in c.units.filter { u in
                [u.id, u.symbol, u.name, u.name + "s"].map(key).contains(k) || u.aliases.map(key).contains(k) || (u.id.count > 1 && key(u.id) == k)
            }.map { (c.id, $0) } }
        }
        let froms = find(String(text[r2])), tos = find(String(text[r3]))
        for (cat, from) in froms { if let to = tos.first(where: { $0.0 == cat }) { return (cat, from.id, to.1.id, amount) } }
        return nil
    }
}
