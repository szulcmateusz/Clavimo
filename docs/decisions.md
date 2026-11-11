# Decisions

Short records of decisions that shape the project. Each lists the reason and the trade-off accepted.

## Native Swift, SwiftUI and AppKit

Clavimo is a native macOS app. The input path runs in compiled Swift with no scripting runtime, which keeps latency low and avoids shipping a browser engine for a settings window.

## Quartz event tap first, no driver

Input is handled with a session-level `CGEventTap`, a public API that needs no kernel or DriverKit extension and no administrator rights. The trade-off: events do not carry a device identity, Caps Lock and Fn cannot be remapped, and input at the login window is out of reach. A driver-based backend may be explored later as an optional component, never as a requirement.

## Pure, deterministic engine

All decisions about events are made by `InputEngine`, which has no platform dependencies and receives time as input. This makes the down/up lifecycle, modifier state and chord timing testable with synthetic events, and keeps the event tap callback small.

## Fail open

When anything is uncertain (the tap is disabled, the session changes, permissions disappear, the configuration is invalid) Clavimo stops changing input rather than guessing. A rule that cannot run is shown as unsupported, never applied partially. Remapping can always be stopped from the menu bar.

## Primary clicks only with explicit opt-in

Left and right clicks are not observed unless a rule explicitly allows them, and such rules need modifiers. A mistake there could make the mouse unusable.

## Letter key chords need an explicit policy

A letter key used with a mouse button must be buffered or its character reaches the app. Each policy has a cost (delay, no autorepeat, or a stray character), so the user chooses it explicitly and the UI explains it.

## Experimental device attribution by HID state

Device-specific rules are implemented by asking each HID device whether the key or button is currently pressed, without a driver. The answer is used only when exactly one device model reports it; otherwise the rule does not apply. Two identical devices cannot be told apart. This is labeled experimental until verified on more hardware.

## Swift packages instead of an Xcode project

The repository builds with Swift Package Manager and small scripts that assemble and sign the app bundle. This keeps the build reviewable as text and usable from the command line and CI. Xcode can open each package directly.

## Local signing identity for development

macOS ties privacy permissions to the code signature. A self-signed identity in a dedicated keychain keeps permissions across rebuilds without an Apple Developer account. Release builds will need a separate decision about Developer ID signing and notarization.

## No telemetry

Clavimo makes no network connections. Diagnostics are aggregate and local.

## Name

The project was developed under the working name Modweave and renamed to Clavimo (Latin *clavis*, key, plus mouse) after checking package registries, the App Store, GitHub and domains for conflicts. A formal trademark search is still recommended before a public release.
