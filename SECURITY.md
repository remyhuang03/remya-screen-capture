# Security Policy

## Supported versions

Security fixes are prioritized for the latest release and the default branch. Older
releases may receive fixes where practical.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/remyhuang03/remya-screen-capture/security/advisories/new).
Keep vulnerability details out of issues and pull requests. Include the affected version
or commit, environment, expected security boundary, observed impact, and sanitized
evidence. Remove credentials, private data, and sensitive logs.

Coordinate disclosure with the maintainer so they can verify the report and prepare a
fix.

## Scope

Remy'a Screen Capture handles screen and audio content, temporary media, exports,
clipboard data and subprocesses such as GPU Screen Recorder and FFmpeg. Report boundary
violations such as capture beyond the selected target or recording options, or file and
clipboard operations outside the action the user requested.

Report standalone dependency vulnerabilities to the upstream project. Report exposure
specific to this application's integration here.
