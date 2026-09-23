import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(SoccerZone)
public final class SoccerZone: NSObject {
    @objc public var zoneIdentifier: String { "soccer" }
    @objc public var zoneTitle: String { "Soccer" }
    @objc public var zoneSymbol: String { "soccerball" }
    @objc public var zonePreferredWidth: NSNumber { 320 }
    @objc public var zonePreferredHeight: NSNumber { 272 }
    /// Zones (0.13.1 and later) shows this as a button under Settings → Added Zones → Soccer.
    @objc public var zoneSettingsTitle: String { "Soccer Settings…" }
    @objc public func zoneOpenSettings() { DispatchQueue.main.async { SoccerSettingsController.shared.show() } }
    /// Zones uses the first entry as this zone's starting position, so the list is ordered: free spots first.
    @objc public var zoneAllowedPlacements: [String] { SoccerZone.placementOrder() }
    /// Draws across the whole curved shape (the team dial). The size slider under Settings → Added Zones uses this range.
    @objc public var zoneUsesFullShape: NSNumber { true }
    @objc public var zoneDefaultScale: NSNumber { 1.35 }
    @objc public var zoneMinimumScale: NSNumber { 0.8 }
    @objc public var zoneMaximumScale: NSNumber { 2.0 }

    public override init() {
        super.init()
        // Start fetching (and watching for your teams' games) as soon as Zones starts, even before the zone is opened.
        DispatchQueue.main.async { SoccerStore.shared.start(); SCChip.shared.start() }
    }

    /// A new zone should land on an empty spot: take a read-only look at where Zones' other zones sit and pick the first free one.
    static func placementOrder() -> [String] {
        let preference = ["bottomLeft", "topRight", "bottomRight", "topLeft", "bottom", "top"]
        let d = UserDefaults.standard
        if let saved = d.string(forKey: "sc.defaultPlacement"), preference.contains(saved) { return [saved] + preference.filter { $0 != saved } }
        var used = Set<String>()
        let builtIns: [(String, String, String)] = [
            ("actionEnabled", "placement", "left"), ("todayEnabled", "todayPlacement", "top"), ("audioEnabled", "mediaPlacement", "bottomLeft"),
            ("launchEnabled", "launchPlacement", "bottomRight"), ("communicationsEnabled", "communicationsPlacement", "bottom"),
            ("resourcesEnabled", "resourcesPlacement", "topLeft"), ("controlsEnabled", "controlsPlacement", "right"), ("clipboardEnabled", "clipboardPlacement", "topRight")]
        for (enabledKey, placementKey, fallback) in builtIns where (d.object(forKey: enabledKey) as? Bool ?? (enabledKey == "audioEnabled")) {
            used.insert(d.string(forKey: placementKey) ?? fallback)
        }
        let enabledAdded = d.dictionary(forKey: "installedZoneEnabled") as? [String: Bool] ?? [:]
        let placedAdded = d.dictionary(forKey: "installedZonePlacement") as? [String: String] ?? [:]
        for (id, on) in enabledAdded where on && id != "added.soccer" { used.insert(placedAdded[id] ?? "top") }
        let pick = preference.first { !used.contains($0) } ?? "top"
        d.set(pick, forKey: "sc.defaultPlacement")
        return [pick] + preference.filter { $0 != pick }
    }

    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let placement = (context["placement"] as? String) ?? "top"
        let hit = SCHitMap()
        let host = NSHostingView(rootView: SoccerView(placement: placement, hit: hit))
        host.sizingOptions = []
        let box = SCPassThroughBox(hit: hit)
        host.frame = box.bounds; host.autoresizingMask = [.width, .height]
        box.addSubview(host)
        return box
    }
}
