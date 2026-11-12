# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/). Before 1.0, minor versions may change the configuration format; such changes are listed here.

## [Unreleased]

## [1.4.0] - 2026-11-12

### Added

- Ready-made setups: four tested sets of changes that switch on in one click and off again in one click. MacBook trackpad every day (a middle click and play or pause by tapping, volume by turning two fingers; gestures macOS already uses are left out), Mouse with side buttons (an action compass and Space switching), Switching from Windows (Alt and Windows keys on a PC keyboard, Home and End, Print Screen, the mouse wheel) and For programmers (Caps Lock as Escape and Hyper, arrows under the right hand). Each change has its own switch and explanation; Clavimo checks what is connected and recommends the setups that fit, leaves out any change that would clash with your own rules and says why, and offers Undo right after.
- The welcome guide offers the setups that fit your hardware instead of single rules, and can be shown again from General.
- The Overview recommends two setups for what is connected.

### Fixed

- Rules chosen in the welcome guide were saved one by one, so an error could leave some of them added, and they went to the Default profile instead of the active one.

## [1.3.1] - 2026-11-12

### Changed

- The compass draws one segment per action, as large as the area that picks it: two actions get half the ring each, four a quarter.

## [1.3.0] - 2026-11-12

### Added

- Action compass: up to eight actions around the pointer. Hold a key or mouse button, move towards an action and let go; after a moment the compass shows its actions and highlights the one that will run. A tap, a trackpad gesture or the menu bar opens it as a panel, where a click, Return, the number keys 1 to 8 or Escape decide. Compasses have pages for apps, can open other compasses, come with templates (Spaces and windows, music, browsers, code editors, Zoom) and are edited in the new Compass pane or pasted from an AI assistant.
- Choose a menu item of the frontmost app as an action, also for commands without a shortcut, picked from the app's menus in the editor.
- Side mouse buttons (3 and up) can run an action on their own, without a modifier.

### Changed

- The configuration file keeps top-level fields that this version does not know when it is saved, so files from newer versions lose nothing. Versions before 1.3.0 drop `compasses` when they save the file.
- While a rule opens a compass, left and right clicks pass through the event tap so a click can pick or close it. Pointer movement is still never observed by the tap; the pointer position is read only while a compass is open.

## [1.2.4] - 2026-11-12

### Added

- Paste Rules, in Rules and in General > Backup and Import: paste rules an AI assistant wrote, or any Clavimo rules in JSON, without saving a file. One long JSON or several separate rules pasted one after another are accepted (a whole configuration, lists of rules or single rules), also inside Markdown code blocks; missing IDs, names and profiles are filled in, and every change is shown before it is applied.

### Fixed

- Only one copy of Clavimo runs at a time. Two copies each ran every rule, so a key or gesture could act twice; a second launch now quits and leaves the running copy in charge.

## [1.2.3] - 2026-11-12

First public release of the 1.2 features below.

### Added

- German interface.
- Turn two fingers like a knob: clockwise and counterclockwise are gestures of their own, and every further 15 degrees runs the action again, so volume or brightness change smoothly. Trackpad scrolling is held still while fingers turn.
- Trackpad zones: a gesture can do different things on the left, right, top or bottom half of the trackpad, or in one of its corners. A rule for a zone wins over the same gesture anywhere.
- Trackpad templates for volume and brightness by turning two fingers.

### Fixed

- Clavimo 1.2.0 quit right after launch while checking keyboards for a leftover Caps Lock mapping, and its Keyboard pane was missing from the settings sidebar. Versions 1.2.0 to 1.2.2 were tagged but never published.
- Turning two fingers starts only when both fingers move around a center, so a resting thumb or a curved two-finger scroll no longer changes the volume by accident.

## [1.2.0] - 2026-11-11

### Added

- Keyboard pane with Caps Lock choices (Escape, or Escape when tapped and Control or Hyper when held, with Caps Lock on a double tap), home row modifiers, templates and all keyboard rules.
- Tap or hold any key: one output when tapped, another when held, an optional double tap, and a tap output for modifier keys pressed alone. Misfire protection for letter keys: a key of the same hand or fast typing means tap.
- Layers, turned on while a key is held or switched on and off, with the active layer next to the menu bar icon.
- Combos (two or three keys pressed at the same moment), key sequences after a leader key with an on-screen list of the next keys, and one-shot modifiers.
- Keyboard outputs: a key held as long as its trigger, a shortcut, modifiers, a layer, a one-shot modifier, a sequence start, any action, or nothing.
- Caps Lock as a rule trigger. Clavimo moves Caps Lock to F18 at the keyboard level while such rules run and restores it when remapping stops or Clavimo quits.
- Condition on the keyboard input source, and the `toggleCapsLock` action.
- The menu and the Keyboard pane say when secure typing (a password field) pauses keyboard rules, and which app turned it on.
- Japanese keyboard keys (英数, かな) in key pickers; `clavimo-probe keyboard` lists input sources and secure typing.

### Changed

- Modifiers held by keyboard rules (for example a home row ⌘) count for modifier + mouse button rules and trackpad rules.

## [1.1.1] - 2026-11-11

First public release of the 1.1 features below.

### Fixed

- The source builds again with Xcode 16 (Swift 6.0 and 6.1), which did not accept three names in the new trackpad code. Version 1.1.0 was tagged but never published.

## [1.1.0] - 2026-11-11

### Added

- Trackpad gestures as rule triggers: taps with two to five fingers, tip taps beside a resting finger and swipes with three to five fingers, each optionally with held modifiers and app conditions. Experimental; finger positions come from Apple's private MultitouchSupport framework, read only while a trackpad rule is enabled or the Trackpad pane is open, and the feature turns itself off if macOS changes that framework.
- Trackpad clicks with three to five fingers, and clicks or taps in a corner, replaced by an action.
- Trackpad scrolling separate from the mouse wheel: direction per axis, speed and momentum.
- Actions for every rule: click a mouse button, send a keyboard shortcut, open an app, press a media or brightness key.
- Trackpad pane with a live finger preview, templates, trackpad scrolling and warnings about overlapping macOS gestures.
- `clavimo-probe touches` to inspect trackpad data on new macOS versions.


## [1.0.0] - 2026-11-11

First stable release. Features marked Experimental in the README are complete and covered by automated tests but not yet verified on real hardware. Release builds are not notarized by Apple.

### Added

- Redesigned settings window: Overview, Rules, Mouse & Scrolling, Devices, Diagnostics, General and About, with rules drawn as keycaps, mouse buttons and actions and explained in a sentence.
- Original app icon and menu bar icon: a keycap and a mouse linked like chain links.
- First-launch guide for permissions, devices and a first rule from templates.
- Rule templates and a live preview in the rule editor.
- Profiles that inherit the Default rules, with a profile switcher in the menu bar.
- Export, import with a preview of the changes, and restoring the previous configuration.
- Diagnostics: event tap health, processing time percentiles, an opt-in input inspector kept in memory only, and a copyable diagnostic report without typed text.
- Pause for 5 minutes or 1 hour from the menu bar.
- Scroll modes for mouse wheels, configured per axis: system, accelerated with a speed multiplier, a fixed number of lines per notch, (experimental) a fixed number of pixels per notch, and smooth scrolling that glides each notch.
- Polish interface; the app follows the macOS language.
- Keyboard and VoiceOver support in the rules list, and Reduce Motion support.
- Random-input tests of the engine's invariants and a 1000-rule performance test.

### Changed

- Error and validation messages name the rule and keys involved instead of internal identifiers.

## [0.1.0] - 2026-11-11

First preview release. Most features are experimental: they are covered by automated tests but have been verified on only one Mac (macOS 27.2, Apple Silicon). Release builds are not notarized by Apple.

### Added

- Menu bar app that applies keyboard and mouse rules from a per-account configuration file, with pause, emergency disable and safe mode after repeated event tap failures.
- Settings window with a visual rule editor, key recording, a devices list and permission and startup status.
- Rule types: key swaps (including Command and Option, left and right separately), key remaps, modifier + mouse button chords (including Fn and, with explicit opt-in, the left and right buttons), letter key + mouse button chords with three explicit buffering policies, and mouse wheel direction reversal that leaves trackpads unchanged.
- Actions: next and previous Space, Mission Control and application windows through the macOS keyboard shortcuts.
- Rule conditions for frontmost app, excluded apps and (experimental) physical devices.
- Opt-in Launch at Login through `SMAppService`; input handling pauses automatically while another macOS account is active.
- Draft v1 configuration schema, an example configuration and validation tools.

[Unreleased]: https://github.com/szulcmateusz/Clavimo/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/szulcmateusz/Clavimo/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/szulcmateusz/Clavimo/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/szulcmateusz/Clavimo/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/szulcmateusz/Clavimo/releases/tag/v0.1.0
