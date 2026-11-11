# Privacy

Clavimo changes keyboard and mouse input, so it can see sensitive events. This document describes exactly what it does with them. It applies to the current source code; any change to this behavior will be documented here and in the changelog before release.

## What Clavimo processes

- **Keyboard events** (key codes, modifier state, autorepeat), **mouse button events** and, only when a mouse wheel rule is enabled, **scroll events**. Pointer movement is never observed.
- Events are processed in memory, one at a time, to decide whether a rule applies. They are **not stored, logged or transmitted**. Clavimo never records typed text.
- For rules limited to a device, Clavimo asks connected input devices whether a specific key or button is currently pressed. Only the device's vendor and product ID are used.
- To evaluate app conditions, Clavimo keeps the bundle identifier of the frontmost app in memory.

## What is stored

| Data | Location | Contents |
| --- | --- | --- |
| Configuration | `~/Library/Application Support/Clavimo/config.json` | Your rules: key codes, mouse buttons, app bundle IDs and device IDs you chose |
| Configuration backup | `~/Library/Application Support/Clavimo/config.backup.json` | The previous version of the configuration |
| Preferences | `~/Library/Preferences/dev.clavimo.app.plist` | Whether the permission prompt was already shown, and the settings window position |

Clavimo keeps only aggregate timing statistics (for example the 95th percentile callback duration) in memory. They contain no key codes.

## Network

Clavimo makes **no network connections**. There is no telemetry, analytics, crash reporting or update check.

## Permissions

| Permission | Why |
| --- | --- |
| Accessibility | Required to change, replace or suppress keyboard and mouse events. |
| Input Monitoring | Required to observe keyboard events and to read device state for device-specific rules. |

Each macOS account grants permissions separately. You can revoke them at any time in **System Settings > Privacy & Security > Accessibility** and **Input Monitoring**; Clavimo then stops changing input and tells you why.

## Deleting your data

Quit Clavimo, delete `Clavimo.app`, then delete `~/Library/Application Support/Clavimo` and `~/Library/Preferences/dev.clavimo.app.plist`. If you enabled Launch at Login, turn it off in Clavimo first or remove Clavimo in **System Settings > General > Login Items**.
