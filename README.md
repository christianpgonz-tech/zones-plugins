# Making a zone

A zone is a small macOS bundle (`Something.zone`) that Zones loads from
`~/Library/Application Support/Zones/Added Zones`. People get it by downloading
`Something.zip` from your website, then choosing **Add Zone…** in the Zones menu or
Settings → Added Zones.

## Fastest way: copy the Calculator example
1. Copy the `Calculator` folder and rename it (e.g. `MoonTracker`).
2. In the `.swift` file change the class name, `zoneIdentifier` (unique, no spaces),
   `zoneTitle` (unique — it can't match any built-in zone or another added zone) and the SwiftUI view.
3. In `Info.plist` change `CFBundleName`, `CFBundleExecutable`, `CFBundleIdentifier`,
   `NSPrincipalClass` (= your class name) and the summary.
4. In `build.sh` change `NAME=` and the `.swift` file name, then run `./build.sh`.
5. Upload the resulting `.zip` to your website.

## What the app reads (names must match exactly)
`zoneIdentifier`, `zoneTitle`, `zoneSymbol` (SF Symbol), `zonePreferredWidth/Height`,
`zoneAllowedPlacements` (any of top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight),
and `makeViewWithContext(_:)` returning an `NSView` (wrap SwiftUI in `NSHostingView`).

## Good to know
- Distributing to other people: a plain build is ad-hoc signed. It loads because Zones removes the
  download quarantine when the user explicitly adds it. If Zones is later notarized with a Developer ID,
  build zones with the same Developer ID team.
- Updating a zone that's already running takes effect after Zones restarts (macOS can't unload code).
- A zone runs with the same access as the app — only publish zones you wrote.

## Custom icon
Put a `ZoneIcon.png` (a black shape on a transparent background, about 128 px tall) in the zone's folder;
`build.sh` bundles it, and Zones draws it on the zone's handle in the same colour as the other icons.
Without one, the SF Symbol from `zoneSymbol` is used.

## Optional settings for bigger zones (used by Periodic Table)
`zoneUsesFullShape` (true = your view fills the whole half/quarter circle and is rebuilt when the zone moves to another edge;
the view's size tells you the radius, and `context["placement"]` says which edge),
`zoneDefaultScale`, `zoneMinimumScale`, `zoneMaximumScale` (starting size and the Size slider's range).

## Shared sports picker
`ZonePlugins/Shared/SportsPicker.swift` is compiled into NFL Football, College Football and Soccer (each `build.sh` lists it),
so all three have the same team picker: a dial with the groups (divisions, conferences, leagues) as rim sections, filter buttons,
search (a magnifier in the zone, a search box in settings), one-group circles, stars, double-click for details. A zone plugs in by making
its team type conform to `PickerTeam` and its store to `PickerStore` (see `CollegePicker.swift`). Each zone is still one download.
