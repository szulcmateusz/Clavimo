# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/). Before 1.0, minor versions may change the configuration format; such changes are listed here.

## [Unreleased]

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

[Unreleased]: https://github.com/szulcmateusz/Clavimo/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/szulcmateusz/Clavimo/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/szulcmateusz/Clavimo/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/szulcmateusz/Clavimo/releases/tag/v0.1.0
