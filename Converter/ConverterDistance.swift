import AppKit
import SwiftUI

/// Great-circle distance between two points on Earth — not a proportional conversion, so it's a calculator screen.
enum GeoMath {
    static let earthRadiusKm = 6371.0088

    static func haversineKm(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180, dLon = (b.lon - a.lon) * .pi / 180
        let la1 = a.lat * .pi / 180, la2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }
    /// A rough estimate only: real flights climb, cruise, descend, and route around weather/airspace — this assumes a
    /// steady 550 mph (a typical jet cruise speed) point-to-point, plus a flat 30 minutes for takeoff/climb/descent/landing.
    static func flightMinutes(km: Double) -> Double { (km / 1.60934 / 550) * 60 + 30 }
}

struct GeoPlace: Identifiable, Hashable {
    let id: String       // display name (cities) or IATA code (airports)
    let label: String
    let lat: Double
    let lon: Double
}

enum GeoData {
    static let cities: [GeoPlace] = [
        GeoPlace(id: "New York", label: "New York, US", lat: 40.7128, lon: -74.0060),
        GeoPlace(id: "Los Angeles", label: "Los Angeles, US", lat: 34.0522, lon: -118.2437),
        GeoPlace(id: "Chicago", label: "Chicago, US", lat: 41.8781, lon: -87.6298),
        GeoPlace(id: "Miami", label: "Miami, US", lat: 25.7617, lon: -80.1918),
        GeoPlace(id: "Mexico City", label: "Mexico City, MX", lat: 19.4326, lon: -99.1332),
        GeoPlace(id: "Santiago", label: "Santiago, CL", lat: -33.4489, lon: -70.6693),
        GeoPlace(id: "Buenos Aires", label: "Buenos Aires, AR", lat: -34.6037, lon: -58.3816),
        GeoPlace(id: "São Paulo", label: "São Paulo, BR", lat: -23.5505, lon: -46.6333),
        GeoPlace(id: "Bogotá", label: "Bogotá, CO", lat: 4.7110, lon: -74.0721),
        GeoPlace(id: "Lima", label: "Lima, PE", lat: -12.0464, lon: -77.0428),
        GeoPlace(id: "London", label: "London, UK", lat: 51.5072, lon: -0.1276),
        GeoPlace(id: "Paris", label: "Paris, FR", lat: 48.8566, lon: 2.3522),
        GeoPlace(id: "Madrid", label: "Madrid, ES", lat: 40.4168, lon: -3.7038),
        GeoPlace(id: "Berlin", label: "Berlin, DE", lat: 52.5200, lon: 13.4050),
        GeoPlace(id: "Rome", label: "Rome, IT", lat: 41.9028, lon: 12.4964),
        GeoPlace(id: "Amsterdam", label: "Amsterdam, NL", lat: 52.3676, lon: 4.9041),
        GeoPlace(id: "Moscow", label: "Moscow, RU", lat: 55.7558, lon: 37.6173),
        GeoPlace(id: "Dubai", label: "Dubai, AE", lat: 25.2048, lon: 55.2708),
        GeoPlace(id: "Cairo", label: "Cairo, EG", lat: 30.0444, lon: 31.2357),
        GeoPlace(id: "Cape Town", label: "Cape Town, ZA", lat: -33.9249, lon: 18.4241),
        GeoPlace(id: "Nairobi", label: "Nairobi, KE", lat: -1.2921, lon: 36.8219),
        GeoPlace(id: "Mumbai", label: "Mumbai, IN", lat: 19.0760, lon: 72.8777),
        GeoPlace(id: "Delhi", label: "Delhi, IN", lat: 28.7041, lon: 77.1025),
        GeoPlace(id: "Bangkok", label: "Bangkok, TH", lat: 13.7563, lon: 100.5018),
        GeoPlace(id: "Singapore", label: "Singapore, SG", lat: 1.3521, lon: 103.8198),
        GeoPlace(id: "Hong Kong", label: "Hong Kong, HK", lat: 22.3193, lon: 114.1694),
        GeoPlace(id: "Tokyo", label: "Tokyo, JP", lat: 35.6762, lon: 139.6503),
        GeoPlace(id: "Seoul", label: "Seoul, KR", lat: 37.5665, lon: 126.9780),
        GeoPlace(id: "Beijing", label: "Beijing, CN", lat: 39.9042, lon: 116.4074),
        GeoPlace(id: "Shanghai", label: "Shanghai, CN", lat: 31.2304, lon: 121.4737),
        GeoPlace(id: "Sydney", label: "Sydney, AU", lat: -33.8688, lon: 151.2093),
        GeoPlace(id: "Auckland", label: "Auckland, NZ", lat: -36.8509, lon: 174.7645),
        GeoPlace(id: "Toronto", label: "Toronto, CA", lat: 43.6532, lon: -79.3832),
    ]
    static let airports: [GeoPlace] = [
        GeoPlace(id: "JFK", label: "JFK · New York", lat: 40.6413, lon: -73.7781),
        GeoPlace(id: "LAX", label: "LAX · Los Angeles", lat: 33.9416, lon: -118.4085),
        GeoPlace(id: "ORD", label: "ORD · Chicago", lat: 41.9742, lon: -87.9073),
        GeoPlace(id: "MIA", label: "MIA · Miami", lat: 25.7959, lon: -80.2870),
        GeoPlace(id: "SFO", label: "SFO · San Francisco", lat: 37.6213, lon: -122.3790),
        GeoPlace(id: "MEX", label: "MEX · Mexico City", lat: 19.4363, lon: -99.0721),
        GeoPlace(id: "SCL", label: "SCL · Santiago", lat: -33.3930, lon: -70.7858),
        GeoPlace(id: "EZE", label: "EZE · Buenos Aires", lat: -34.8222, lon: -58.5358),
        GeoPlace(id: "GRU", label: "GRU · São Paulo", lat: -23.4356, lon: -46.4731),
        GeoPlace(id: "BOG", label: "BOG · Bogotá", lat: 4.7016, lon: -74.1469),
        GeoPlace(id: "LIM", label: "LIM · Lima", lat: -12.0219, lon: -77.1143),
        GeoPlace(id: "LHR", label: "LHR · London", lat: 51.4700, lon: -0.4543),
        GeoPlace(id: "CDG", label: "CDG · Paris", lat: 49.0097, lon: 2.5479),
        GeoPlace(id: "MAD", label: "MAD · Madrid", lat: 40.4983, lon: -3.5676),
        GeoPlace(id: "FRA", label: "FRA · Frankfurt", lat: 50.0379, lon: 8.5622),
        GeoPlace(id: "AMS", label: "AMS · Amsterdam", lat: 52.3105, lon: 4.7683),
        GeoPlace(id: "FCO", label: "FCO · Rome", lat: 41.8003, lon: 12.2389),
        GeoPlace(id: "SVO", label: "SVO · Moscow", lat: 55.9736, lon: 37.4125),
        GeoPlace(id: "DXB", label: "DXB · Dubai", lat: 25.2532, lon: 55.3657),
        GeoPlace(id: "CAI", label: "CAI · Cairo", lat: 30.1219, lon: 31.4056),
        GeoPlace(id: "CPT", label: "CPT · Cape Town", lat: -33.9715, lon: 18.6021),
        GeoPlace(id: "JNB", label: "JNB · Johannesburg", lat: -26.1392, lon: 28.2460),
        GeoPlace(id: "BOM", label: "BOM · Mumbai", lat: 19.0896, lon: 72.8656),
        GeoPlace(id: "DEL", label: "DEL · Delhi", lat: 28.5562, lon: 77.1000),
        GeoPlace(id: "BKK", label: "BKK · Bangkok", lat: 13.6900, lon: 100.7501),
        GeoPlace(id: "SIN", label: "SIN · Singapore", lat: 1.3644, lon: 103.9915),
        GeoPlace(id: "HKG", label: "HKG · Hong Kong", lat: 22.3080, lon: 113.9185),
        GeoPlace(id: "NRT", label: "NRT · Tokyo", lat: 35.7719, lon: 140.3929),
        GeoPlace(id: "ICN", label: "ICN · Seoul", lat: 37.4602, lon: 126.4407),
        GeoPlace(id: "PEK", label: "PEK · Beijing", lat: 40.0799, lon: 116.6031),
        GeoPlace(id: "PVG", label: "PVG · Shanghai", lat: 31.1443, lon: 121.8083),
        GeoPlace(id: "SYD", label: "SYD · Sydney", lat: -33.9399, lon: 151.1753),
        GeoPlace(id: "AKL", label: "AKL · Auckland", lat: -37.0082, lon: 174.7850),
        GeoPlace(id: "YYZ", label: "YYZ · Toronto", lat: 43.6777, lon: -79.6248),
    ]
}

struct DistanceCalcView: View {
    @State private var airportMode: Bool
    init(startAirports: Bool = false) { _airportMode = State(initialValue: startAirports) }
    @State private var fromID = "New York"
    @State private var toID = "London"
    @State private var fromAirport = "JFK"
    @State private var toAirport = "LHR"

    private var list: [GeoPlace] { airportMode ? GeoData.airports : GeoData.cities }
    private var from: GeoPlace? { list.first { $0.id == (airportMode ? fromAirport : fromID) } }
    private var to: GeoPlace? { list.first { $0.id == (airportMode ? toAirport : toID) } }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                tool(airportMode ? "Airport Distance & Flight Time" : "City Distance", airportMode ? "airplane" : "mappin.and.ellipse") {
                    Picker("", selection: $airportMode) { Text("Cities").tag(false); Text("Airports").tag(true) }
                        .pickerStyle(.segmented).labelsHidden()
                    if airportMode {
                        Picker("From", selection: $fromAirport) { ForEach(list) { Text($0.label).tag($0.id) } }
                        Picker("To", selection: $toAirport) { ForEach(list) { Text($0.label).tag($0.id) } }
                    } else {
                        Picker("From", selection: $fromID) { ForEach(list) { Text($0.label).tag($0.id) } }
                        Picker("To", selection: $toID) { ForEach(list) { Text($0.label).tag($0.id) } }
                    }
                    if let a = from, let b = to, a.id != b.id {
                        let km = GeoMath.haversineKm((a.lat, a.lon), (b.lat, b.lon))
                        row("Distance", "\(Convert.format(km.rounded())) km  ·  \(Convert.format((km / 1.60934).rounded())) mi")
                        if airportMode {
                            let mins = GeoMath.flightMinutes(km: km)
                            row("Est. flight time", NetMath.formatDuration(mins * 60))
                        }
                    } else if from?.id == to?.id { Text("Pick two different places.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Text(airportMode
                     ? "Straight-line (great-circle) distance, not an actual flight route. Flight time assumes a steady 550 mph cruise speed plus 30 minutes for takeoff and landing — real flights vary with routing, wind, and airspace."
                     : "Straight-line (great-circle) distance between city centers, not driving distance.")
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
