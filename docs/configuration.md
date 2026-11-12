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
| `deviceSettings` | Mouse wheel and trackpad scrolling settings (below). |
| `compasses` | Optional. Action compasses (below). |
| `macros` | Reserved; macros are not supported yet. |

Rules that are enabled but cannot run are listed as unsupported in the menu and the settings window. They are never applied partially.

## Rules

Every rule has `id`, `name`, `enabled`, `priority`, `profileId`, `trigger`, `conditions`, `action`, `behavior` and `ui`. Keys use `{"codeNamespace": "macVirtualKeyCode", "code": N}` (macOS virtual key codes). Mouse buttons are numbered from 1: 1 is the left button, 2 the right, 3 the middle, 4 and 5 are usually back and forward.

| Rule | `trigger.kind` | `action.kind` | Notes |
| --- | --- | --- | --- |
| Swap two keys | `keyPair` | `swapKeys` | Both directions. Left and right modifiers are distinct keys. `sideMode: both` is not supported; add one rule per side. |
| Remap a key | `key` | `sendKey` | Caps Lock (code 57) can be remapped; no rule can send Caps Lock or Fn. |
| Key with another output | `key` | any keyboard output (below) | A shortcut, modifiers, a layer, a one-shot modifier, a sequence start, an action or `none`. Not for modifier keys. |
| Tap or hold a key | `tapHold` | `tapHold` | See [keyboard rules](#keyboard-rules-tap-hold-layers-combos-and-sequences). |
| Key on a layer | `layerKey` with `layerId` and `key` | any keyboard output | |
| Keys pressed together | `keyCombo` with two or three `keys` | any keyboard output | |
| Key sequence | `keySequence` with one to four `keys` | any keyboard output | Runs after a key with `startSequence`. |
| Modifier + mouse button | `modifierChord` with `requiredModifiers` and `mouseButton` | any action (below) | Modifiers: `control`, `option`, `shift`, `command`, `function`. The held set must match exactly. Buttons 1 and 2 require `behavior.allowProtectedButton: true`. |
| Mouse button | `mouseButton` with `mouseButton` and optional `requiredModifiers` | any action | Buttons 3 and up can act alone; without modifiers the button no longer does its usual job. Buttons 1 and 2 need a modifier, like a modifier chord. |
| Key + mouse button | `keyMouseChord` with `leaderKey`, `mouseButton`, `order: leaderThenMouse` | any action | Requires `behavior.leaderPolicy` (below). |
| Trackpad gesture | `trackpadGesture` (below) | any action | Experimental. |
| Trackpad click | `trackpadClick` (below) | any action | Experimental. Replaces the click. |

Chords and trackpad rules require `behavior` `{"consumeTrigger": true, "fireOn": "down", "repeat": "once"}`.

### Actions

| `action` | Effect |
| --- | --- |
| `{"kind": "nextWorkspace"}`, `previousWorkspace`, `missionControl`, `applicationWindows` | Posts the macOS Mission Control shortcuts (Control + arrow keys), which must be enabled in Keyboard Shortcuts. |
| `{"kind": "sendShortcut", "key": {...}, "modifiers": ["command"]}` | Presses a keyboard shortcut. |
| `{"kind": "mouseClick", "mouseButton": 3}` | Clicks a mouse button at the pointer (3 is the middle button, 4 back, 5 forward). |
| `{"kind": "launchApp", "bundleId": "com.apple.Safari"}` | Opens or activates an app. |
| `{"kind": "mediaKey", "key": "playPause"}` | Presses a media key: `playPause`, `nextTrack`, `previousTrack`, `volumeUp`, `volumeDown`, `mute`, `brightnessUp`, `brightnessDown`. Brightness keys may not work with external displays. |
| `{"kind": "toggleCapsLock"}` | Turns Caps Lock on or off. |
| `{"kind": "openCompass", "compassId": "main"}` | Opens an [action compass](#action-compasses). Held keys and buttons pick by direction when released; taps, chords with modifiers and gestures open it as a panel. |
| `{"kind": "menuItem", "path": ["File", "New Tab"]}` | Chooses an item in the frontmost app's menus, by its titles from the menu bar down. Titles must match the app's language; case and a trailing ellipsis do not matter. Works for items without a shortcut. |

### Trackpad gestures and clicks

Experimental. Finger positions come from Apple's private MultitouchSupport framework (see [decisions](decisions.md)); if it is missing or changes, trackpad rules do nothing and everything else keeps working.

| `trigger` | Meaning |
| --- | --- |
| `{"kind": "trackpadGesture", "gesture": "tap", "fingers": 3}` | Fingers (2-5) touch down together and lift quickly without moving. A two-finger tap is the macOS secondary click, so it needs `requiredModifiers`. |
| `{"kind": "trackpadGesture", "gesture": "tipTap", "side": "right"}` | One finger rests while another taps to its `left` or `right`. |
| `{"kind": "trackpadGesture", "gesture": "swipe", "fingers": 3, "direction": "left"}` | Fingers (3-5) move together `up`, `down`, `left` or `right`. One swipe per touch. |
| `{"kind": "trackpadGesture", "gesture": "rotate", "direction": "clockwise"}` | Two fingers turn like a knob, `clockwise` or `counterclockwise`. The first step needs about 34 degrees with both fingers moving around a center (a resting finger or a two-finger scroll does not count), then every further 15 degrees runs the action again, so a media key such as `volumeUp` changes smoothly. While fingers turn, trackpad scrolling is held still. |
| `{"kind": "trackpadClick", "fingers": 3}` | The trackpad is pressed with this many fingers (3-5). The click is replaced by the action. |
| `{"kind": "trackpadClick", "corner": "topRight"}` | One finger clicks, or taps with tap to click, in a corner: `topLeft`, `topRight`, `bottomLeft`, `bottomRight`. |

Gestures accept `"zone"`: a half (`"left"`, `"right"`, `"top"`, `"bottom"`) or a corner quarter (`"topLeft"`, `"topRight"`, `"bottomLeft"`, `"bottomRight"`). The rule applies only when the gesture starts there, so one gesture can have different jobs in different places (for example volume on the left, brightness on the right). A rule with a zone wins over the same gesture without one. Clicks cannot have a zone.

Every trackpad trigger accepts `requiredModifiers`; the held set must match exactly, so a rule without modifiers does not run while a modifier is held. App conditions work as usual; device conditions are not supported. macOS keeps recognizing its own gestures: a rule using a movement macOS also uses (for example three-finger swipes) runs together with the macOS gesture, even while a key is held. The Trackpad pane lists such overlaps.

## Keyboard rules: tap-hold, layers, combos and sequences

Experimental. These rules hold a key back for a moment while Clavimo decides what it means; held-back keys are always delivered, in their original order, by the deadline at the latest. Clicking the mouse decides at once (a held tap-hold key becomes its hold), so a home row modifier works with a click.

### Keyboard outputs

Keyboard rules accept every action above plus these outputs:

| `action` | Effect |
| --- | --- |
| `{"kind": "sendKey", "key": {...}}` | Presses the key for as long as the trigger is held; it repeats like a normal key. |
| `{"kind": "sendShortcut", "key": {...}, "modifiers": ["command"]}` | The key with extra modifiers, held for as long as the trigger. |
| `{"kind": "holdModifiers", "modifiers": ["control", "option", "shift", "command"]}` | Holds modifiers (all four make a Hyper key). Generic names mean the left key; `rightCommand` and similar name a side. |
| `{"kind": "holdLayer", "layerId": "nav"}` | Turns the layer on while held. |
| `{"kind": "toggleLayer", "layerId": "nav"}` | Turns the layer on, or off when it is on. |
| `{"kind": "oneShotModifiers", "modifiers": ["shift"]}` | The next key or click gets these modifiers. They expire after three seconds; pressing it again cancels them. |
| `{"kind": "startSequence"}` | Starts a key sequence (a leader key). |
| `{"kind": "none"}` | Does nothing: the key is disabled. |

### Tap or hold

```json
"trigger": {"kind": "tapHold", "key": {"codeNamespace": "macVirtualKeyCode", "code": 57}, "thresholdMs": 200,
            "interruptPolicy": "anyOtherKey"},
"action": {"kind": "tapHold", "tap": {"kind": "sendKey", "key": {...}}, "hold": {"kind": "holdModifiers", "modifiers": [...]},
           "doubleTap": {"kind": "toggleCapsLock"}}
```

| Field | Meaning |
| --- | --- |
| `thresholdMs` | 50-2000. Held longer than this, the key is a hold. |
| `interruptPolicy` | What another key pressed meanwhile means. `anyOtherKey` (default): a hold at once; best for Caps Lock and Space. `permissiveHold`: a hold only when that other key is also released while this one is held, so overlapping keystrokes while typing stay taps; best for letter keys. `none`: only time decides. |
| `oppositeHandsOnly` | `true`: a key of the same hand pressed meanwhile means tap. Prevents misfires of home row modifiers during rolls. |
| `typingStreakMs` | 0-500. Pressed within this many milliseconds of the previous key, the key is a tap at once. 150 suits most typists. |
| `doubleTap`, `doubleTapMs` | An optional output for two taps within `doubleTapMs` (100-600, default 250). A single tap then waits that long. |

`hold` must be a held output: `holdModifiers`, `holdLayer`, `sendKey` or `sendShortcut`. Tapping the key and pressing it again quickly, then holding, repeats the tap (unless there is a `doubleTap`).

Modifier keys can get a tap output too: `hold` must then be the key's own modifier, for example `{"kind": "holdModifiers", "modifiers": ["rightOption"]}`. The modifier works as usual; the tap output runs when the key is pressed and released alone within `thresholdMs`. Tapping Left Command for 英数 (code 102) and Right Command for かな (code 104) works this way.

**Caps Lock.** macOS toggles Caps Lock below the level apps and Clavimo see. While a rule uses Caps Lock (code 57), Clavimo moves Caps Lock to F18 on every keyboard through the same HID setting `hidutil` and the Modifier Keys settings use, and removes that setting when remapping stops or the app quits. A keyboard whose Caps Lock is changed in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys is left alone and listed in the Keyboard pane. In apps where no Caps Lock rule applies, Caps Lock keeps toggling. If Clavimo stops without cleaning up (for example after a crash), Caps Lock types nothing until Clavimo starts again or you log out.

### Layers

A layer is a set of `layerKey` rules that apply while the layer is on. Keys not on the layer work as usual, and physically held modifiers still apply (Shift + a layer arrow selects text). A layer must be turned on by some rule (`holdLayer` or `toggleLayer`), otherwise the configuration is rejected. While a layer is on, its name appears next to the menu bar icon.

### Combos

`keyCombo` keys pressed within `windowMs` (20-200, default 50) of each other run the output instead. Each combo key is held back for up to `windowMs` when typed alone, so keep the window short. Modifier keys cannot be part of a combo.

### Sequences

A key with `startSequence` (a `key` rule, a tap output, or a layer key) starts a sequence; then `keySequence` rules match the keys typed next. A panel near the bottom of the screen lists the keys that can come next. Escape, a key that matches nothing, a click or four seconds without a key cancel the sequence. No sequence may be the start of another one.

### Leader policies for key + mouse button

A letter key used as a chord leader must be held back briefly, otherwise its character would reach the app before Clavimo knows a click is coming.

| `leaderPolicy` | Behavior |
| --- | --- |
| `boundedWindow` | The key is held back for `leaderWindowMs` (50-500, default 120). A click inside the window triggers the action; otherwise the key types, slightly delayed, and repeats normally. |
| `deferredUntilUp` | The key types only when released, never by accident, but does not repeat while held. |
| `nonConsuming` | The key types immediately and the chord still works, but the character reaches the app. |

The leader is only held back in apps where at least one of its chords can apply.

## Action compasses

A compass holds up to eight actions around the pointer, one per direction. A rule with the action `openCompass` opens it.

- **Hold and move.** While the trigger (a key, a mouse button, or a tap-hold key's hold) is held, move the pointer towards an action and let go: it runs at once. After `hintDelayMs` the compass shows its actions and highlights the one that would run. Letting go inside `deadZone` after holding cancels; a short tap without moving keeps the compass open as a panel.
- **Panel.** Opened by a tap, a gesture or the menu bar. The direction of the pointer from the middle highlights an action; a click, Return or Space runs it, the number keys 1 to 8 (clockwise from up) run one directly, and Escape, a right click or the trigger again close the compass. Any other key closes it and types normally.

```json
"compasses": [{
  "id": "main",
  "name": "Main",
  "slots": [
    {"direction": "up", "action": {"kind": "missionControl"}},
    {"direction": "left", "name": "Back", "action": {"kind": "sendShortcut", "key": {"codeNamespace": "macVirtualKeyCode", "code": 33}, "modifiers": ["command"]}},
    {"direction": "upRight", "name": "Music", "action": {"kind": "openCompass", "compassId": "media"}}
  ],
  "apps": [{"bundleId": "com.apple.Safari", "slots": [
    {"direction": "up", "name": "New tab", "action": {"kind": "menuItem", "path": ["File", "New Tab"]}},
    {"direction": "upRight", "action": {"kind": "none"}}
  ]}],
  "hintDelayMs": 250,
  "deadZone": 40,
  "returnPointer": true
}]
```

| Field | Meaning |
| --- | --- |
| `id`, `name` | `id` is what `openCompass` refers to; `name` is shown in the middle of the compass. |
| `slots` | Up to eight `{direction, name, action}` entries. `direction` is `up`, `upRight`, `right`, `downRight`, `down`, `downLeft`, `left` or `upLeft`. `name` is optional; without it the compass shows what the action does. With fewer slots, each one covers a wider angle. |
| `apps` | Pages for apps by `bundleId`. A direction on an app page replaces the default page's slot in that app; `{"kind": "none"}` hides it; directions not listed keep the default page's slot. |
| `hintDelayMs` | 0-2000, default 250. How long the trigger is held before the actions are shown. |
| `deadZone` | 10-200 points, default 40. Pointer travel below this picks nothing. |
| `returnPointer` | Default `true`. Puts the pointer back where it was after an action picked by moving. |

A slot can open another compass (`openCompass`), which then appears in the same place as a panel. Rules that open a missing compass, and slots with an unknown direction or action, are reported as unsupported and left out. While a compass is open Clavimo reads the pointer position to know the direction; it never records pointer movement otherwise.

## Conditions

`conditions` is a list combined with AND:

| Condition | Meaning |
| --- | --- |
| `{"kind": "appIs", "bundleId": "com.apple.Safari"}` | Only while this app is frontmost. Several entries mean any of them. |
| `{"kind": "appIsNot", "bundleId": "..."}` | Never while this app is frontmost. |
| `{"kind": "physicalDeviceIs", "deviceId": "1133:49298"}` | Experimental. Only for input from this device (`vendorId:productId` in decimal, see `--list-devices`). If the device cannot be determined, the rule does not apply. Not available for key + mouse button rules. |
| `{"kind": "inputSourceIs", "inputSourceId": "com.apple.keylayout.PolishPro"}` | Only while this keyboard input source is selected. Several entries mean any of them. `clavimo-probe keyboard` lists the identifiers. |

When several mouse chords share a trigger, the higher `priority` wins; for equal priority, the rule with more specific conditions wins, then the earlier rule. Key swaps and remaps for the same key must have different conditions; the most specific matching rule wins (a device condition is more specific than app conditions).

## Device settings: trackpad scrolling

```json
{
  "id": "...", "name": "Trackpad", "enabled": true, "profileId": "default", "priority": 50,
  "scope": {"deviceClass": "trackpad"},
  "scrolling": {
    "vertical": {"reverse": true, "mode": "accelerated", "speedMultiplier": 1.5},
    "horizontal": {"reverse": false, "mode": "accelerated", "speedMultiplier": 1.5},
    "momentum": false
  }
}
```

Changes continuous scrolling from trackpads and Magic Mouse, separately from mouse wheels. Each axis can be reversed; `mode` is `system` or `accelerated` with one `speedMultiplier` (0.25-4) for both axes; `momentum: false` stops scrolling as soon as the fingers lift. Scroll phases are kept, so apps still see complete gestures. `scope.appBundleId` limits the setting to one app.

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

Changes discrete mouse wheel scrolling; each axis is configured separately. Continuous scrolling from trackpads and Magic Mouse has its own setting (above). `scope.appBundleId` limits the setting to one app.

| `mode` | Field | Behavior |
| --- | --- | --- |
| `system` | | Distance and acceleration as set in macOS. |
| `accelerated` | `speedMultiplier` (0.1-10) | The macOS acceleration curve, scaled. |
| `byLines` | `distanceLines` (1-30) | A fixed number of lines per wheel notch, without acceleration. |
| `byPixels` | `distancePixels` (1-512) | Experimental. A fixed number of pixels per wheel notch, delivered as precise scrolling. |
| `smoothed` | `distancePixels` (10-300, default 60), `smoothing.response` (0.05-1.0 seconds, default 0.25) | Each notch glides `distancePixels` over about `response` seconds with an ease-out curve. Scrolling the other way, using the trackpad, pausing or switching users stops the animation; pending distance is capped at 25 notches and an animation never runs longer than 3 seconds. |

`reverse` inverts the axis in any mode. In `byLines` and `byPixels`, movements smaller than one line from high-resolution wheels are ignored so they do not each count as a full notch.

Not supported yet: the `acceleration` field, `smoothing` fields other than `response`, per-device scope (`vendorId`/`productId`), `displayId`, and pointer speed and acceleration.
