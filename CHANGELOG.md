# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/). Before 1.0, minor versions may change the configuration format; such changes are listed here.

## [Unreleased]

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
