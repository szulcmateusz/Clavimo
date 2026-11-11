# Configuration reference

Clavimo stores its configuration per macOS account in:

```text
~/Library/Application Support/Clavimo/config.json
```

The settings window is the normal way to edit it. The file is plain JSON and can also be edited by hand; use **Reload Configuration** in the menu afterwards. The format is version 1 (`schemaVersion` 1), described by [`schema/config-v1.schema.json`](../schema/config-v1.schema.json); any future change to it will be listed in the changelog. [`examples/example-config.json`](../examples/example-config.json) shows every supported rule type.

Check a file without touching input:

```sh
/Applications/Clavimo.app/Contents/MacOS/Clavimo --check-config [path]
/Applications/Clavimo.app/Contents/MacOS/Clavimo --list-devices
```

## Document

| Field | Meaning |
| --- | --- |
| `engine.enabledOnLaunch` | Turn remapping on when the app starts. |
| `activeProfileId` | Only rules and device settings with this `profileId` are used. Profile inheritance is not supported yet. |
| `rules` | Keyboard and mouse rules (below). |
| `deviceSettings` | Mouse wheel settings (below). |
| `macros` | Reserved; macros are not supported yet. |

Rules that are enabled but cannot run are listed as unsupported in the menu and the settings window. They are never applied partially.

## Rules

Every rule has `id`, `name`, `enabled`, `priority`, `profileId`, `trigger`, `conditions`, `action`, `behavior` and `ui`. Keys use `{"codeNamespace": "macVirtualKeyCode", "code": N}` (macOS virtual key codes). Mouse buttons are numbered from 1: 1 is the left button, 2 the right, 3 the middle, 4 and 5 are usually back and forward.

| Rule | `trigger.kind` | `action.kind` | Notes |
| --- | --- | --- | --- |
| Swap two keys | `keyPair` | `swapKeys` | Both directions. Left and right modifiers are distinct keys. `sideMode: both` is not supported; add one rule per side. |
| Remap a key | `key` | `sendKey` | |
| Modifier + mouse button | `modifierChord` with `requiredModifiers` and `mouseButton` | `nextWorkspace`, `previousWorkspace`, `missionControl`, `applicationWindows` | Modifiers: `control`, `option`, `shift`, `command`, `function`. The held set must match exactly. Buttons 1 and 2 require `behavior.allowProtectedButton: true`. |
| Key + mouse button | `keyMouseChord` with `leaderKey`, `mouseButton`, `order: leaderThenMouse` | same as above | Requires `behavior.leaderPolicy` (below). |

Chords require `behavior` `{"consumeTrigger": true, "fireOn": "down", "repeat": "once"}`.

Caps Lock and Fn cannot be remapped yet.

### Leader policies for key + mouse button

A letter key used as a chord leader must be held back briefly, otherwise its character would reach the app before Clavimo knows a click is coming.

| `leaderPolicy` | Behavior |
| --- | --- |
| `boundedWindow` | The key is held back for `leaderWindowMs` (50-500, default 120). A click inside the window triggers the action; otherwise the key types, slightly delayed, and repeats normally. |
| `deferredUntilUp` | The key types only when released, never by accident, but does not repeat while held. |
| `nonConsuming` | The key types immediately and the chord still works, but the character reaches the app. |

The leader is only held back in apps where at least one of its chords can apply.

## Conditions

`conditions` is a list combined with AND:

| Condition | Meaning |
| --- | --- |
| `{"kind": "appIs", "bundleId": "com.apple.Safari"}` | Only while this app is frontmost. Several entries mean any of them. |
| `{"kind": "appIsNot", "bundleId": "..."}` | Never while this app is frontmost. |
| `{"kind": "physicalDeviceIs", "deviceId": "1133:49298"}` | Experimental. Only for input from this device (`vendorId:productId` in decimal, see `--list-devices`). If the device cannot be determined, the rule does not apply. Not available for key + mouse button rules. |

When several mouse chords share a trigger, the higher `priority` wins; for equal priority, the rule with more specific conditions wins, then the earlier rule. Key swaps and remaps for the same key must have different conditions; the most specific matching rule wins (a device condition is more specific than app conditions).

## Device settings: mouse wheel

```json
{
  "id": "...", "name": "Mouse wheel", "enabled": true, "profileId": "default", "priority": 50,
  "scope": {"deviceClass": "mouse"},
  "scrolling": {
    "vertical": {"reverse": true, "mode": "byLines", "distanceLines": 3},
    "horizontal": {"reverse": false, "mode": "system"}
  }
}
```

Changes discrete mouse wheel scrolling; each axis is configured separately. Continuous scrolling from trackpads and Magic Mouse is never changed. `scope.appBundleId` limits the setting to one app.

| `mode` | Field | Behavior |
| --- | --- | --- |
| `system` | | Distance and acceleration as set in macOS. |
| `accelerated` | `speedMultiplier` (0.1-10) | The macOS acceleration curve, scaled. |
| `byLines` | `distanceLines` (1-30) | A fixed number of lines per wheel notch, without acceleration. |
| `byPixels` | `distancePixels` (1-512) | Experimental. A fixed number of pixels per wheel notch, delivered as precise scrolling. |
| `smoothed` | `distancePixels` (10-300, default 60), `smoothing.response` (0.05-1.0 seconds, default 0.25) | Each notch glides `distancePixels` over about `response` seconds with an ease-out curve. Scrolling the other way, using the trackpad, pausing or switching users stops the animation; pending distance is capped at 25 notches and an animation never runs longer than 3 seconds. |

`reverse` inverts the axis in any mode. In `byLines` and `byPixels`, movements smaller than one line from high-resolution wheels are ignored so they do not each count as a full notch.

Not supported yet: the `acceleration` field, `smoothing` fields other than `response`, per-device scope (`vendorId`/`productId`), `displayId`, and pointer speed and acceleration.
