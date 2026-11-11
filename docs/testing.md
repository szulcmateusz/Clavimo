# Testing

## Automated tests

Each package has a Swift Testing suite, run in CI on every push and pull request:

```sh
swift test --package-path Packages/ClavimoCore    # engine, compiler, configuration, scrolling
swift test --package-path Packages/ClavimoQuartz  # flag conversion, event masks, latency recorder
swift test --package-path Packages/ClavimoApp     # status logic, rule form, configuration editor, import diff
python3 scripts/check-translations.py             # every string translated, placeholders intact
```

The engine tests cover key down/up pairing after rule changes, reference-counted outputs, left and right modifier swaps held and released in any order, all three leader policies including late timers, chord release orders, resets during held keys, app and device conditions, and compiler validation.

**Random input.** `EnginePropertyTests` plays 600 seeded random sessions of 400 events each against four rule sets: presses, releases and repeats of keys and buttons, chord windows expiring, app switches, rule reloads and resets. After every event, every key up must match an earlier key down and the modifier flags on each event must match the modifier keys apps have seen; once everything is released, nothing may stay held and the engine must be idle. Failures name the seed, so they can be replayed. Breaking the engine on purpose (for example, releasing a shared output while another key still holds it) makes these tests fail.

**Trackpad.** `GestureRecognizerTests` plays scripted finger movements for every gesture and the cases that must not be gestures (slow taps, moving fingers, fingers landing far apart, diagonal movement, slow three-finger drags, two-finger scrolling), plus 300 random touch sessions after which the recognizer must be idle and every reported gesture must match the fingers it saw. `TrackpadRuleTests` cover modifiers, app conditions, priorities and replaced clicks; the random engine sessions include trackpad click rules. `TouchDecodingTests` check the private structure offsets and that implausible data turns the backend off.

**Performance.** `EnginePerformanceTests` compiles 1000 app-scoped rules and handles 50,000 events, failing if the average exceeds 50 µs per event in a debug build.

**Scrolling.** `SmoothScrollerTests` checks that the animation covers exactly the requested distance, stops on reversal, and respects the distance and time limits; `ScrollTransformTests` covers every scroll mode.

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
11. **Smooth scrolling.** With **Smooth** selected in Mouse & Scrolling, each wheel notch glides; scrolling the other way stops at once; the trackpad still scrolls normally and stops a running glide.
12. **Scroll modes.** By lines and accelerated scroll by the configured amount in Safari, Finder and a terminal.
13. **Profiles.** Switching the profile from the menu bar applies its rules at once, including while a remapped key is held (it is released correctly).
14. **Backup.** Export, then import the same file: the preview shows no changes. Change a rule and use Restore Previous Version: the change is undone.
15. **First launch.** On an account without Clavimo settings, the guide appears, its permission page updates by itself, and a template creates a working rule.
16. **Input inspector.** Shows keys and buttons with what Clavimo did, and is empty after leaving Diagnostics.
17. **Language.** With Polish as the macOS language, the whole interface is in Polish without cut-off labels.
18. **Trackpad data.** `clavimo-probe touches --seconds 15 --raw` lists the trackpad, decodes fingers in 0-1 coordinates with y growing upwards, and reports no invalid frames.
19. **Trackpad gestures.** The Trackpad pane's live preview names three- and four-finger taps, tip taps on both sides and swipes in four directions; typing, pointing, two-finger scrolling and slow three-finger drags produce no gestures.
20. **Trackpad clicks.** With a three-finger click rule, a three-finger click runs the action and ordinary clicks, drags and right clicks are unchanged. A corner rule works with a physical click and with tap to click.
21. **Trackpad scrolling.** Reversing vertical trackpad scrolling does not change the mouse wheel; turning momentum off stops scrolling when the fingers lift.

### Results

| Date | macOS | Mac | Hardware | Items | Result |
| --- | --- | --- | --- | --- | --- |
| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Built-in keyboard (Polish Pro layout), Logitech G102 (USB) | 1 (right Command and Option swap, everyday typing) | Works in daily use; reverse release order not yet checked |
| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Built-in keyboard, Logitech G102 (USB) | Probe latency, 180 s of normal use, 1127 events | Pass-through callback p50 8.4 µs, p95 14.5 µs, p99 42.2 µs; handled events p95 414 µs; no tap timeouts |

| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Logitech G102 (USB) | 5 (wheel reversed, 3 lines per notch) | Works in daily use; trackpad not explicitly checked |

| 2026-11-11 | 27.2 (26B123) | MacBook Pro, Apple M1 Pro | Built-in Force Touch trackpad (family 105) | 18 (probe, 15 s) | 884 valid frames, none invalid; 96-byte records decode at the expected offsets; top right corner reads x 0.98, y 0.94, so y grows upwards; three fingers detected |

Not yet verified: items 2 to 4, 6 to 17 and 19 to 21, Intel Macs, Magic Trackpad, macOS versions other than 27.2, Bluetooth and Logitech receiver devices.

### Latency measurement

`clavimo-probe run --seconds N` records the duration of every event tap callback in a fixed-size buffer and prints percentiles for events passed through unchanged and events Clavimo changed. The numbers cover Clavimo's own processing only, not USB, Bluetooth or display latency.
