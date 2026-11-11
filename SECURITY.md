# Security Policy

Clavimo observes and changes keyboard and mouse input, so security issues are taken seriously.

## Supported versions

Only the latest release receives security fixes. Fixes are made on the `main` branch first.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Include the affected version or commit, macOS version, and steps to reproduce.

The project is maintained by one person in their spare time. Reports will be acknowledged as soon as possible, but no response time is guaranteed.

## What not to send

Never include passwords, private text, or recordings of everything you typed in a report, even a private one. Describe keys by name (for example "Right Command") and redact app names you consider private.

## Scope

In scope: anything that lets Clavimo log or leak input, process input without the user's permission, run code from a configuration file, interfere with another macOS account's session, or leave keys or buttons stuck in a way the documented recovery cannot fix.

Out of scope: behavior that requires an attacker who already controls your user account, and issues in macOS or third-party tools.
