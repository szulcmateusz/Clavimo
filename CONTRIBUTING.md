# Contributing to Clavimo

Thanks for your interest in improving Clavimo. This guide explains how to build the project, what a good change looks like, and how to submit it.

## Prerequisites

- A Mac running macOS 14 or later.
- Xcode 16 or later (Swift 6). The command line tools alone are not enough to run the tests reliably.
- Optional: Python 3 with `jsonschema` to validate configuration files.

If Xcode is not your active developer directory, either run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` or prefix commands with `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

## Project layout

| Path | Contents |
| --- | --- |
| `Packages/ClavimoCore` | Platform-independent rule engine, rule compiler and configuration model. Pure Swift, fully unit tested. |
| `Packages/ClavimoQuartz` | macOS input backend: event tap, event conversion, device discovery and attribution, shortcut actions. Also contains `clavimo-probe`, a diagnostic tool. |
| `Packages/ClavimoApp` | The menu bar app and settings window. |
| `schema/` | JSON schema for the configuration file. |
| `examples/` | Example configurations; CI checks them. |
| `scripts/` | Build, signing, validation and commit message tools. |
| `docs/` | Architecture, configuration reference, decisions and testing notes. |

## Build and test

```sh
swift test --package-path Packages/ClavimoCore
swift test --package-path Packages/ClavimoQuartz
swift test --package-path Packages/ClavimoApp
scripts/build-app.sh                 # builds build/Clavimo.app
scripts/build-app.sh --install       # also installs and restarts it
```

macOS ties Accessibility and Input Monitoring permissions to the app's code signature. Ad-hoc signatures change on every build, so permissions would have to be granted again after each rebuild. To avoid that, create a local, self-signed signing identity once:

```sh
scripts/setup-local-signing.sh
```

It lives in its own keychain under `~/Library/Application Support/ClavimoDev` and is used automatically by the build scripts.

Validate configuration files:

```sh
python3 -m venv .venv && .venv/bin/pip install jsonschema
.venv/bin/python scripts/validate-config.py examples/example-config.json
build/Clavimo.app/Contents/MacOS/Clavimo --check-config examples/example-config.json
```

## Testing on real hardware

Automated tests cover the engine with synthetic events. Anything that depends on macOS, keyboards or mice must also be checked by hand before it is called supported. Describe what you tested (macOS version, Mac model, keyboard and mouse, connection type) in your pull request. Do not claim compatibility or performance results you did not measure. See [docs/testing.md](docs/testing.md) for the manual checklist.

`clavimo-probe` runs the event tap with fixed rules for a limited time and prints only aggregate latency figures:

```sh
scripts/build-probe-app.sh
scripts/run-probe.sh status
scripts/run-probe.sh run --seconds 60
```

## Coding guidelines

- Keep the event path minimal: no allocation-heavy work, file or network access, logging of key data, or UI updates inside the event tap callback.
- Input must fail open. Every consumed key or button down needs a matching resolution of its up, including after rule changes, pauses and session switches.
- Never log, store or transmit typed text or raw key sequences.
- Prefer pure, testable logic in `ClavimoCore` and add tests for every behavior change.
- Public APIs, comments and UI strings are written in English.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) in English:

```text
feat(rules): support keyboard and mouse chords
fix(input): release held modifiers when the event tap stops
```

Allowed types are `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `style` and `revert`. Keep the subject at most 72 characters, use the imperative mood, and explain why in the body when it is not obvious. Use only the ASCII hyphen `-`, never en or em dashes. Enable the local check with:

```sh
git config core.hooksPath scripts/git-hooks
```

## Pull requests

1. Open an issue first for larger changes, new rule types or new backends.
2. Keep pull requests small and focused, with tests and documentation updated.
3. Fill in the pull request template, including how you tested and any latency or privacy impact.
4. CI must pass.

## Reporting bugs and security issues

Use the issue templates for bugs and feature requests. Never attach passwords, private text or key logs. Report security problems privately as described in [SECURITY.md](SECURITY.md).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
