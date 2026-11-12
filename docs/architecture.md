# Architecture

Clavimo is split into three Swift packages so that the logic that decides what happens to an input event can be tested without macOS input permissions.

```text
┌──────────────────────────────────────────────────────────────┐
│ ClavimoApp (menu bar app, settings window)                    │
│  AppDelegate ── AgentStatus ── ConfigStore ── ConfigEditor    │
└───────────────┬──────────────────────────────────────────────┘
                │ CompiledRules (immutable snapshot)
┌───────────────▼──────────────────────────────────────────────┐
│ ClavimoQuartz (macOS backend)                                 │
│  EventTapController ── QuartzFlags ── HIDDeviceAttributor     │
│  SystemShortcutExecutor (actions, off the event path)         │
└───────────────┬──────────────────────────────────────────────┘
                │ InputEvent / EngineOutput
┌───────────────▼──────────────────────────────────────────────┐
│ ClavimoCore (pure Swift)                                      │
│  InputEngine (state machine) ── CompiledRules ── ConfigV1     │
└──────────────────────────────────────────────────────────────┘
```

## ClavimoCore

- **`InputEngine`** is a deterministic state machine. It receives normalized `InputEvent`s and returns an `EngineOutput`: an ordered list of items (forward the original event, possibly with corrected modifier flags, or emit key events), actions to run, and an optional deadline for buffered leader keys. Time is injected; the engine performs no I/O.
- **Lifecycle guarantees.** A remapped key's up event always resolves through the mapping that was active at key down, even after the rules change. Output keys held by several physical keys are reference counted. `reset()` moves the logical key state back to the physical state for pause, panic and session switches.
- **Modifier remapping** is done by tracking logical modifier state: physical modifiers minus remapped sources plus remapped targets. Every forwarded event carries the logical flags, so a swapped Command never leaks into shortcuts.
- **`CompiledRules`** is an immutable lookup structure built by `CompiledRules.compile`, which also rejects conflicting or unsafe rules (duplicate triggers with equal conditions, unprotected primary clicks, out-of-range windows, unsupported keys).
- **`ConfigDocument`** reads and writes the draft v1 configuration file and translates it into rule definitions, reporting anything the engine cannot run instead of applying it partially.

## ClavimoQuartz

- **`EventTapController`** owns one session-level `CGEventTap` on a dedicated run loop thread. All engine access happens on that thread, so the event path needs no locks. The event mask is built from the rules: key and other-mouse-button events always, primary and secondary clicks only for rules that opt in or open an action compass, scroll events only for wheel rules. Pointer movement is never observed by the tap. An open action compass is a session in the engine (`CompassSignal`); the app's `CompassController` reads the pointer position only while it is open, decides the direction with `CompassGeometry` and calls `closeCompass()` when done.
- **Output.** A single modifier output is applied by rewriting the incoming event in place. Other outputs are posted with `CGEventTapPostEvent` and tagged with a source user data value so they pass through unevaluated.
- **Recovery.** When macOS disables the tap (timeout or user input), the engine is reset first, then the tap is re-enabled with a rate limit. Repeated failures stop the tap and the app enters safe mode.
- **`HIDDeviceAttributor`** implements experimental device attribution: for keys and buttons used by device-scoped rules it asks each open HID device whether the key or button is currently pressed (`IOHIDDeviceGetValue`). The result is used only if exactly one device model reports it.
- **`SystemShortcutExecutor`** runs actions by posting the documented Control + Arrow shortcuts on a separate queue.

## ClavimoApp

- **`AgentStatus`** combines independent inputs (user enabled, active console session, permissions, valid rules, safe mode) into one status. The event tap runs only when the status is `active`. This is what lets the app pause for another macOS account and resume on its own.
- **`ConfigStore`** validates the whole document with the engine's compiler before replacing the file atomically, and keeps the previous file as a backup.
- **Settings window** (SwiftUI) edits rules through `RuleDraft`, which converts between the form and the configuration format and preserves rules it cannot represent.

## Event path budget

The callback converts the event, runs the engine and applies its output. It does not allocate on the pass-through path, log, touch files, call into the UI, or wait for actions. Callback durations are recorded in a fixed-size buffer for the probe's latency report.
