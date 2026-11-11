# Testing

## Automated tests

Each package has a Swift Testing suite, run in CI on every push and pull request:

```sh
swift test --package-path Packages/ClavimoCore    # engine, compiler, configuration
swift test --package-path Packages/ClavimoQuartz  # flag conversion, event masks, latency recorder
swift test --package-path Packages/ClavimoApp     # status logic, rule form, configuration editor
```

The engine tests cover key down/up pairing after rule changes, reference-counted outputs, left and right modifier swaps held and released in any order, all three leader policies including late timers, chord release orders, resets during held keys, app and device conditions, and compiler validation.

## Manual hardware verification

Behavior that depends on macOS, keyboards and mice has to be checked by hand. Results are recorded below with the exact environment. A feature is listed as verified only after it has been tried; everything else stays experimental.

### Checklist

1. **Command and Option swap.** In TextEdit, swapped Command + A selects all; swapped Option + letter types the expected character. Hold both swapped keys and release them in reverse order: no modifier stays held.
2. **Modifier + click.** With Fn or Control + Command held, left and right clicks switch Spaces; ordinary clicks, drags and right-click menus keep working.
3. **Side buttons.** Modifier + button 4 or 5 runs the action and does not also go back or forward in a browser.
4. **Letter key chord.** Type text containing the leader letter quickly: no letter is lost or duplicated. Hold the letter and click within the window: the action runs and no letter appears.
5. **Mouse wheel.** Wheel direction is reversed; trackpad direction is unchanged.
6. **Device rules.** A rule limited to one keyboard does not apply on another.
7. **Pause and recovery.** Pause and Emergency Disable restore normal input immediately, also while a remapped key is held. Quitting the app (or force quitting it in Activity Monitor) restores normal input.
8. **Session switching.** With two macOS accounts, switch A to B to A repeatedly while holding keys: only the active account's rules apply, nothing stays held, and no manual restart is needed.
9. **Sleep and wake.** Rules work after waking the Mac.
10. **Coexistence.** With Karabiner-Elements or Logi Options+ running, the warning appears; record any interference.

### Results

| Date | macOS | Mac | Hardware | Items | Result |
| --- | --- | --- | --- | --- | --- |
| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Built-in keyboard (Polish Pro layout), Logitech G102 (USB) | 1 (right Command and Option swap, everyday typing) | Works in daily use; reverse release order not yet checked |
| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Built-in keyboard, Logitech G102 (USB) | Probe latency, 180 s of normal use, 1127 events | Pass-through callback p50 8.4 µs, p95 14.5 µs, p99 42.2 µs; handled events p95 414 µs; no tap timeouts |

Not yet verified: items 2 to 10, Intel Macs, macOS versions other than 27.2, Bluetooth and Logitech receiver devices.

### Latency measurement

`clavimo-probe run --seconds N` records the duration of every event tap callback in a fixed-size buffer and prints percentiles for events passed through unchanged and events Clavimo changed. The numbers cover Clavimo's own processing only, not USB, Bluetooth or display latency.
