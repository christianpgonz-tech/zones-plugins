import AppKit
import SwiftUI
import Carbon.HIToolbox

/// The timer's own settings window (opened from the gear in the zone, or from the right-click menu).
final class TimerSettingsController {
    static let shared = TimerSettingsController()
    private var window: NSPanel?

    /// Opens Zones' own Settings window, where each added zone has a Size slider (Settings → Added Zones → Focus Timer).
    static func openZonesSettings() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettings")), to: nil, from: nil)
    }

    func show() {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 780),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Focus Timer Settings"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.hidesOnDeactivate = false
            w.isFloatingPanel = true
            w.minSize = NSSize(width: 460, height: 480)
            w.contentView = NSHostingView(rootView: TimerSettingsView(model: TimerModel.shared))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("FocusTimerSettings") { w.center() }
            w.setFrameAutosaveName("FocusTimerSettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TimerSettingsView: View {
    @ObservedObject var model: TimerModel

    var body: some View {
        Form {
            Section {
                ForEach(0..<4, id: \.self) { i in
                    Stepper(value: Binding(get: { max(1, model.presets[i] / 60) }, set: { model.setPreset(i, minutes: $0) }), in: 1...999) {
                        HStack { Text("Timer \(i + 1)"); Spacer(); Text("\(max(1, model.presets[i] / 60)) min").foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
            } header: { Text("Your four timers") } footer: {
                Text("These are the four slices on the dial. You can also right-click a slice to change it.")
            }

            Section("When time is up") {
                Toggle("Play a sound", isOn: $model.soundOn)
                HStack {
                    Picker("Sound", selection: $model.soundName) { ForEach(TimerModel.soundNames, id: \.self) { Text($0).tag($0) } }
                        .disabled(!model.soundOn)
                    Button("Play") { model.play(model.soundName) }.disabled(!model.soundOn)
                }
                Toggle("Pulse the zone", isOn: $model.pulseOn)
            }

            Section {
                Toggle("5 minutes before the end", isOn: $model.warn5)
                Toggle("1 minute before the end", isOn: $model.warn1)
            } header: { Text("Early warning") } footer: {
                Text("A soft chime and a gentle pulse, so the end never surprises you.")
            }

            Section("Snooze") {
                Stepper(value: $model.snoozeMinutes, in: 1...120) {
                    HStack { Text("Add"); Spacer(); Text("\(model.snoozeMinutes) min").foregroundStyle(.secondary).monospacedDigit() }
                }
            }

            Section {
                HotkeyRow(title: "Snooze the alarm", combo: $model.snoozeKey, other: model.stopKey)
                HotkeyRow(title: "Stop the alarm", combo: $model.stopKey, other: model.snoozeKey)
            } header: { Text("Keyboard shortcuts") } footer: {
                Text("Use ⌘, ⌃ or ⌥ with a key. Shortcuts work from any app, but only while the alarm is ringing.")
            }

            Section {
                HStack {
                    Text("Make the zone bigger or smaller")
                    Spacer()
                    Button("Open Zones Settings…") { TimerSettingsController.openZonesSettings() }
                }
            } header: { Text("Size") } footer: {
                Text("In Zones Settings, choose Added Zones, then Focus Timer, and use the Size slider. To move the zone, drag its small handle, or press and hold the empty middle of the open zone and drag.")
            }

            Section {
                Button("Restore defaults", role: .destructive) { model.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A button that records the next key combination you press.
struct HotkeyRow: View {
    let title: String
    @Binding var combo: KeyCombo?
    let other: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Button(recording ? "Press a shortcut…" : (combo?.display ?? "Click to set")) { recording ? stop() : start() }
                    .buttonStyle(.bordered).monospacedDigit()
                if combo != nil && !recording {
                    Button { combo = nil; note = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Remove shortcut")
                }
            }
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.orange) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        note = ""; recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }                        // Esc cancels
            let mods = KeyCombo.carbonFlags(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            let needed = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
            guard mods & needed != 0 else { note = "Add ⌘, ⌃ or ⌥ so it doesn't clash with typing."; return nil }
            let new = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            if new == other { note = "That shortcut is already used by the other action."; return nil }
            combo = new; note = ""; stop(); return nil
        }
    }
    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
