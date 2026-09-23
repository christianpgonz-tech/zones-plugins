import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(CollegeBasketballZone)
public final class CollegeBasketballZone: NSObject {
    @objc public var zoneIdentifier: String { "college-basketball" }
    @objc public var zoneTitle: String { "College Basketball" }
    @objc public var zoneSymbol: String { "basketball.fill" }
    @objc public var zonePreferredWidth: NSNumber { 320 }
    @objc public var zonePreferredHeight: NSNumber { 236 }
    /// Zones (0.13.1 and later) shows this as a button under Settings → Added Zones → College Basketball.
    @objc public var zoneSettingsTitle: String { "College Basketball Settings…" }
    @objc public func zoneOpenSettings() { DispatchQueue.main.async { CollegeBasketballSettingsController.shared.show() } }
    /// Zones uses the first entry as this zone's starting position, so the list is ordered: free spots first.
    @objc public var zoneAllowedPlacements: [String] { CollegeBasketballZone.placementOrder() }
    /// Draws across the whole curved shape (the team dial). The size slider under Settings → Added Zones uses this range.
    @objc public var zoneUsesFullShape: NSNumber { true }
    @objc public var zoneDefaultScale: NSNumber { 1.35 }
    @objc public var zoneMinimumScale: NSNumber { 0.8 }
    @objc public var zoneMaximumScale: NSNumber { 2.0 }

    public override init() {
        super.init()
        SportBadgeLayout.reference = "College Basketball"
        // Start fetching (and watching for your teams' games) as soon as Zones starts, even before the zone is opened.
        DispatchQueue.main.async { CollegeBasketballStore.shared.start(); CollegeBasketballChip.shared.start() }
    }

    /// A new zone should land on an empty spot: take a read-only look at where Zones' other zones sit and pick the first free one.
    static func placementOrder() -> [String] {
        let preference = ["bottomLeft", "topRight", "bottomRight", "topLeft", "bottom", "top"]
        let d = UserDefaults.standard
        if let saved = d.string(forKey: "cb.defaultPlacement"), preference.contains(saved) { return [saved] + preference.filter { $0 != saved } }
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
        for (id, on) in enabledAdded where on && id != "added.college-basketball" { used.insert(placedAdded[id] ?? "top") }
        let pick = preference.first { !used.contains($0) } ?? "top"
        d.set(pick, forKey: "cb.defaultPlacement")
        return [pick] + preference.filter { $0 != pick }
    }

    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let placement = (context["placement"] as? String) ?? "top"
        let hit = CollegeBasketballHitMap()
        let host = NSHostingView(rootView: CollegeBasketballView(placement: placement, hit: hit))
        host.sizingOptions = []
        let box = CollegeBasketballPassThroughBox(hit: hit)
        host.frame = box.bounds; host.autoresizingMask = [.width, .height]
        box.addSubview(host)
        return box
    }
}
