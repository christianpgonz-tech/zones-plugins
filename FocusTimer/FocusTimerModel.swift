import AppKit
import Carbon.HIToolbox
import Combine

// MARK: - Keyboard shortcuts (global, no special permission: registered with macOS hot-key service)

struct KeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32          // Carbon flags: cmdKey, shiftKey, optionKey, controlKey

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCombo.name(for: keyCode)
    }
    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
    private static let names: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    static func name(for code: UInt32) -> String { names[code] ?? "Key \(code)" }
}

/// Registers up to a few global hot keys. They are only registered while an alarm is ringing, so the timer never
/// holds on to a shortcut you might want for something else.
final class HotKeys {
    static let shared = HotKeys()
    var onPress: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeys.shared.onPress?(id.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
    func register(id: UInt32, combo: KeyCombo?) {
        unregister(id: id)
        guard let combo else { return }
        install()
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x46544D52), id: id)   // 'FTMR'
        if RegisterEventHotKey(combo.keyCode, combo.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs[id] = ref }
    }
    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
    func unregisterAll() { for id in Array(refs.keys) { unregister(id: id) } }
}

// MARK: - The timer

enum TimerPhase { case idle, running, paused, alarm, overtime }

/// One timer at a time. Counts down; once it passes zero it keeps counting into negative time ("overtime")
/// so you can see how far past your original time you are.
final class TimerModel: ObservableObject {
    static let shared = TimerModel()
    static let defaultPresets = [300, 900, 1800, 3600]               // seconds: 5, 15, 30, 60 minutes
    static let soundNames = ["Glass", "Ping", "Submarine", "Hero", "Funk", "Blow", "Bottle", "Frog", "Morse", "Pop", "Purr", "Sosumi", "Tink", "Basso"]
    static let snoozeID: UInt32 = 1, stopID: UInt32 = 2

    private let d = UserDefaults.standard
    @Published var phase: TimerPhase = .idle
    @Published var remaining: TimeInterval = 0        // negative once past zero
    @Published var original: TimeInterval = 0
    @Published var added: TimeInterval = 0            // total time added by snoozing / +5
    @Published var activeSlice: Int?
    @Published var warnPulseUntil = Date.distantPast

    // Settings (saved automatically)
    @Published var presets: [Int] { didSet { d.set(presets, forKey: "ft.presets") } }
    @Published var soundOn: Bool { didSet { d.set(soundOn, forKey: "ft.soundOn") } }
    @Published var soundName: String { didSet { d.set(soundName, forKey: "ft.soundName") } }
    @Published var pulseOn: Bool { didSet { d.set(pulseOn, forKey: "ft.pulseOn") } }
    @Published var warn5: Bool { didSet { d.set(warn5, forKey: "ft.warn5") } }
    @Published var warn1: Bool { didSet { d.set(warn1, forKey: "ft.warn1") } }
    @Published var snoozeMinutes: Int { didSet { d.set(snoozeMinutes, forKey: "ft.snoozeMinutes") } }
    @Published var snoozeKey: KeyCombo? { didSet { save(snoozeKey, "ft.hk.snooze"); refreshHotKeys() } }
    @Published var stopKey: KeyCombo? { didSet { save(stopKey, "ft.hk.stop"); refreshHotKeys() } }

    private var ticker: Timer?
    private var last = Date()
    private var warned5 = false, warned1 = false
    private var ringTimer: Timer?
    private var started = false
    /// Hidden testing aid: `defaults write <app> ft.timeScale 60` makes a 5-minute timer run in 5 seconds.
    private var timeScale: Double { let v = d.double(forKey: "ft.timeScale"); return v > 0 ? v : 1 }

    private init() {
        let p = d.array(forKey: "ft.presets") as? [Int]
        presets = (p?.count == 4 ? p! : TimerModel.defaultPresets).map { max(5, min($0, 999 * 60)) }
        soundOn = d.object(forKey: "ft.soundOn") as? Bool ?? true
        soundName = d.string(forKey: "ft.soundName") ?? "Glass"
        pulseOn = d.object(forKey: "ft.pulseOn") as? Bool ?? true
        warn5 = d.object(forKey: "ft.warn5") as? Bool ?? false
        warn1 = d.object(forKey: "ft.warn1") as? Bool ?? false
        snoozeMinutes = d.object(forKey: "ft.snoozeMinutes") as? Int ?? 5
        snoozeKey = TimerModel.load(d, "ft.hk.snooze")
        stopKey = TimerModel.load(d, "ft.hk.stop")
        restore()
    }

    // MARK: persistence of a running timer (so quitting or sleeping never loses it)
    private func persist() {
        d.set(phase == .idle ? "" : "\(phase)", forKey: "ft.phase")
        d.set(remaining, forKey: "ft.remaining"); d.set(original, forKey: "ft.original"); d.set(added, forKey: "ft.added")
        d.set(activeSlice ?? -1, forKey: "ft.slice"); d.set(Date().timeIntervalSince1970, forKey: "ft.savedAt")
    }
    private func restore() {
        guard let name = d.string(forKey: "ft.phase"), !name.isEmpty else { return }
        original = d.double(forKey: "ft.original"); added = d.double(forKey: "ft.added")
        let s = d.integer(forKey: "ft.slice"); activeSlice = s >= 0 ? s : nil
        var r = d.double(forKey: "ft.remaining")
        switch name {
        case "paused": phase = .paused
        case "running", "alarm", "overtime":
            r -= Date().timeIntervalSince1970 - d.double(forKey: "ft.savedAt")
            phase = name == "overtime" ? .overtime : (r <= 0 ? .alarm : .running)
        default: return
        }
        remaining = r
        warned5 = remaining <= 300; warned1 = remaining <= 60
        startTicker()
        if phase == .alarm { beginAlarm() }
    }
    private static func load(_ d: UserDefaults, _ key: String) -> KeyCombo? {
        guard d.object(forKey: key + ".key") != nil else { return nil }
        return KeyCombo(keyCode: UInt32(d.integer(forKey: key + ".key")), modifiers: UInt32(d.integer(forKey: key + ".mod")))
    }
    private func save(_ combo: KeyCombo?, _ key: String) {
        if let combo { d.set(Int(combo.keyCode), forKey: key + ".key"); d.set(Int(combo.modifiers), forKey: key + ".mod") }
        else { d.removeObject(forKey: key + ".key"); d.removeObject(forKey: key + ".mod") }
    }

    // MARK: controls
    func start(slice: Int) {
        guard presets.indices.contains(slice) else { return }
        stopRinging()
        original = TimeInterval(presets[slice]); remaining = original; added = 0; activeSlice = slice
        warned5 = original <= 300; warned1 = original <= 60
        phase = .running; last = Date(); startTicker(); persist()
    }
    func togglePause() {
        if phase == .running { phase = .paused } else if phase == .paused { phase = .running; last = Date() }
        persist()
    }
    /// Adds time. From an alarm (or overtime) that means "give me N more minutes from now".
    func snooze(minutes: Int? = nil) {
        let extra = TimeInterval((minutes ?? snoozeMinutes) * 60)
        guard phase != .idle else { return }
        let wasOver = remaining <= 0
        stopRinging()
        remaining = wasOver ? extra : remaining + extra
        added += extra
        warned5 = remaining <= 300; warned1 = remaining <= 60
        if phase != .paused { phase = .running; last = Date() }
        startTicker(); persist()
    }
    /// Silences the alarm; the timer keeps counting into negative time until you reset it.
    func stopAlarm() {
        guard phase == .alarm else { return }
        stopRinging(); phase = .overtime; persist()
    }
    func reset() {
        stopRinging(); phase = .idle; remaining = 0; original = 0; added = 0; activeSlice = nil
        ticker?.invalidate(); ticker = nil; persist()
    }
    func setPreset(_ slice: Int, minutes: Int) {
        guard presets.indices.contains(slice) else { return }
        presets[slice] = max(1, min(minutes, 999)) * 60
    }
    func restoreDefaults() {
        presets = TimerModel.defaultPresets; soundOn = true; soundName = "Glass"; pulseOn = true
        warn5 = false; warn1 = false; snoozeMinutes = 5; snoozeKey = nil; stopKey = nil
    }

    var pulsing: Bool { (phase == .alarm && pulseOn) || warnPulseUntil > Date() }
    var alarmActive: Bool { phase == .alarm }

    // MARK: ticking, warnings, alarm
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
    }
    private func tick() {
        let now = Date(); let dt = now.timeIntervalSince(last); last = now
        guard phase == .running || phase == .alarm || phase == .overtime else { return }
        remaining -= dt * timeScale
        if phase == .running {
            if warn5, !warned5, remaining <= 300 { warned5 = true; warn() }
            if warn1, !warned1, remaining <= 60 { warned1 = true; warn() }
            if remaining <= 0 { phase = .alarm; beginAlarm() }
        }
        if Int(remaining) % 5 == 0 { persist() }
        objectWillChange.send()
    }
    private func warn() {
        warnPulseUntil = Date().addingTimeInterval(3)
        if soundOn { play("Tink") }
    }
    private func beginAlarm() {
        if soundOn { play(soundName); ringTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            guard let self, self.phase == .alarm else { t.invalidate(); return }
            self.play(self.soundName) }
        }
        refreshHotKeys(); persist()
    }
    private func stopRinging() {
        ringTimer?.invalidate(); ringTimer = nil
        HotKeys.shared.unregisterAll()
    }
    func play(_ name: String) {
        guard let s = NSSound(named: NSSound.Name(name)) else { NSSound.beep(); return }
        s.stop(); s.play()
    }
    /// Shortcuts only exist while an alarm is ringing.
    private func refreshHotKeys() {
        HotKeys.shared.unregisterAll()
        guard phase == .alarm else { return }
        HotKeys.shared.register(id: TimerModel.snoozeID, combo: snoozeKey)
        HotKeys.shared.register(id: TimerModel.stopID, combo: stopKey)
    }
    func startServices() {
        guard !started else { return }
        started = true
        HotKeys.shared.onPress = { [weak self] id in
            guard let self else { return }
            if id == TimerModel.snoozeID { self.snooze() } else if id == TimerModel.stopID { self.stopAlarm() }
        }
        ProgressChip.shared.start()
        // Switching the zone off (or removing it) must end any timer and silence its alarm. The zone's small handle window exists
        // only while the zone is on, so if it is gone for a few seconds the timer is reset. The first seconds after launch are
        // skipped while Zones is still putting its windows up.
        let launched = Date()
        var missing = 0
        let w = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.phase != .idle, Date().timeIntervalSince(launched) > 15 else { missing = 0; return }
            let there = NSApp.windows.contains { $0.title == "Focus Timer" && $0.isVisible }
            missing = there ? 0 : missing + 1
            if missing >= 3 { missing = 0; self.reset() }
        }
        RunLoop.main.add(w, forMode: .common)
    }

    // MARK: display helpers
    static func clock(_ seconds: TimeInterval) -> String {
        let neg = seconds < 0
        let s = Int(abs(seconds).rounded(.down))
        let text = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
        return (neg ? "−" : "") + text
    }
    static func label(_ seconds: Int) -> (String, String) {
        if seconds % 3600 == 0, seconds >= 3600 * 2 { return ("\(seconds / 3600)", "hours") }
        if seconds % 60 == 0 { return ("\(seconds / 60)", "min") }
        return ("\(seconds)", "sec")
    }
}
