# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/). Before 1.0, minor versions may change the configuration format; such changes are listed here.

## [Unreleased]

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

[Unreleased]: https://github.com/szulcmateusz/Clavimo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/szulcmateusz/Clavimo/releases/tag/v0.1.0
