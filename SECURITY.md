# Security Policy

## Supported versions

Security fixes are prioritized for the latest release and the default branch.
Older releases are not guaranteed to receive backports. If the problem is
observable only on an older release, you can still report it privately.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/remyhuang03/remya-screen-capture/security/advisories/new).
Please keep vulnerability details out of public issues and pull requests.
Include the affected release or commit, your environment, the expected security
boundary, the observed impact, and enough information to verify it with
sanitized evidence. Never include credentials or private recordings.

The maintainer will use the private report to discuss verification, a fix, and
disclosure with you. Please coordinate before publishing details.

## Scope

Remy'a Screen Capture is a local Linux desktop app for Hyprland. Reports can
cover its Flutter UI, Linux runner, Rust capture backend, media and clipboard
handling, and the way it invokes external programs such as GPU Screen Recorder
and FFmpeg. Relevant inputs include paths, media files, and data returned by
desktop services or helper processes.

Report issues where a realistic action or input can cross a security boundary.
For example, capture should respect the selected target and recording options;
temporary and exported media should stay within the intended storage flow;
and file handling, clipboard writes, and subprocess calls should honor the
user's requested action. Explain any access or user interaction required and
which data or operation is affected.

Ordinary capture failures and UI bugs can go to the public issue tracker.
Report standalone dependency vulnerabilities to the upstream project. If this
app's integration exposes users to a dependency issue, report that exposure
here as well.
