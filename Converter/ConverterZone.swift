import AppKit
import SwiftUI

// The app reads these names by string, so they must stay exactly as written.
@objc(ConverterZone)
public final class ConverterZone: NSObject {
    @objc public var zoneIdentifier: String { "converter" }
    @objc public var zoneTitle: String { "Converter" }
    @objc public var zoneSymbol: String { "arrow.left.arrow.right.circle" }
    @objc public var zonePreferredWidth: NSNumber { 320 }
    @objc public var zonePreferredHeight: NSNumber { 236 }
    @objc public var zoneSettingsTitle: String { "Converter Settings…" }
    @objc public func zoneOpenSettings() { DispatchQueue.main.async { ConverterSettingsController.shared.show() } }
    /// Free spots first; never the middle of the left or right edge.
    @objc public var zoneAllowedPlacements: [String] { ConverterZone.placementOrder() }
    /// Draws across the whole curved shape (the category dial). The size slider under Settings → Added Zones uses this range.
    @objc public var zoneUsesFullShape: NSNumber { true }
    @objc public var zoneDefaultScale: NSNumber { 1.35 }
    // Below 1.0 (100%), the panel's own header/text can't shrink to match how much smaller the circle
    // just got (buttons stop being reliably tappable under a certain point size — see HeaderBar's own
    // `hs` floor), so its height stops shrinking in proportion while the circle keeps shrinking under
    // it — the panel's bottom then runs past the visible edge. 100% is as small as that stays true.
    @objc public var zoneMinimumScale: NSNumber { 1.0 }
    @objc public var zoneMaximumScale: NSNumber { 2.0 }

    public override init() {
        super.init()
        DispatchQueue.main.async { Rates.shared.load() }
    }

    /// A new zone should land on an empty spot: take a read-only look at where Zones' other zones sit and pick the first free one.
    static func placementOrder() -> [String] {
        let preference = ["bottomLeft", "topRight", "bottomRight", "topLeft", "bottom", "top"]
        let d = UserDefaults.standard
        if let saved = d.string(forKey: "cv.defaultPlacement"), preference.contains(saved) { return [saved] + preference.filter { $0 != saved } }
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
        for (id, on) in enabledAdded where on && id != "added.converter" { used.insert(placedAdded[id] ?? "top") }
        let pick = preference.first { !used.contains($0) } ?? "top"
        d.set(pick, forKey: "cv.defaultPlacement")
        return [pick] + preference.filter { $0 != pick }
    }

    @objc public func makeViewWithContext(_ context: NSDictionary) -> NSView {
        let placement = (context["placement"] as? String) ?? "top"
        let hit = ConverterHitMap()
        let host = FirstMouseHostingView(rootView: ConverterView(placement: placement, hit: hit))
        host.sizingOptions = []
        let box = ConverterBox(hit: hit)
        host.frame = box.bounds; host.autoresizingMask = [.width, .height]
        box.addSubview(host)
        return box
    }
}

/// Hides this zone's own hover panel while its Settings window is open (so it isn't in the way), then brings it back
/// when Settings closes. Only affects Converter's own window, not any other zone or the app itself.
private var converterPanelWindow: NSWindow?
private var settingsCloseObserver: Any?
func hideAndShowSettings() {
    let window = converterPanelWindow
    window?.orderOut(nil)
    ConverterSettingsController.shared.show()
    if let observer = settingsCloseObserver { NotificationCenter.default.removeObserver(observer) }
    if let settingsWindow = ConverterSettingsController.shared.window {
        settingsCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: settingsWindow, queue: .main) { _ in
            window?.orderFrontRegardless()
        }
    }
}

/// A real click on a button here is what AppKit actually hit-tests (not the `ConverterBox` wrapper around it, whose own
/// `acceptsFirstMouse` override only ever governs a click that lands on truly empty space) — so on a non-activating,
/// non-key hover panel, the very first click on any SwiftUI button would otherwise just bring the window forward without
/// firing the button's action, requiring a second click. This override is what makes that first click actually count.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The wrapper: presses on empty space fall through to Zones, and typing goes to whatever is open (the amount, a search, or the quick line).
final class ConverterBox: NSView {
    let hit: ConverterHitMap
    private var monitor: Any?
    init(hit: ConverterHitMap) { self.hit = hit; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p), hit.contains(p) else { return nil }
        return super.hitTest(point)
    }
    /// A click here should act immediately, even if the panel isn't key yet (it's a non-activating hover panel) — without this, the
    /// first click only brings the panel forward and the button underneath doesn't fire until a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { converterPanelWindow = window }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if event.type == .leftMouseDown { if !window.isKeyWindow { window.makeKey() }; return event }
            guard window.isKeyWindow, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let key: String
            switch event.keyCode {
            case 36, 76: key = "↩"
            case 51, 117: key = "⌫"
            case 53: key = "⎋"
            default:
                guard let c = event.characters, c.count == 1, c.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) }) else { return event }
                key = c
            }
            return Conv.shared.key(key) ? nil : event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
