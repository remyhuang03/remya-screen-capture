# Agent Instructions & Development Guidelines

## Project Scope
- `remya_screen_capture` is a screen capture tool for Hyprland on Linux, using Flutter and Rust.
- The project provides screen, window, and region capture with Material Design 3 Expressive UI and native Rust performance backends.
- Application ID is `top.remya.screen_capture`. The executable is `remya_screen_capture`.
- Add real capture behavior and platform integrations only when required by a concrete task.

## Architecture: Monorepo + Feature-first + Rust Workspace
- Keep Flutter at the repository root and manage Rust crates through the root `Cargo.toml` workspace.
- Organize Flutter code under `lib/features/<feature>/`, keeping each feature's UI, state, and data access together. Add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`.
- Put Rust crates under `lib/src/rust/<crate>/`. Group backend functionality by feature; create crates only for concrete responsibility or dependency boundaries.
- `lib/src/rust/core/` is the initial empty backend crate. Do not turn it into a catch-all for unrelated features.
- Future feature backends use `flutter_rust_bridge` 2.13.0; add `flutter_rust_bridge.yaml` and use the matching generator when a concrete Rust API is introduced.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually.

## Core Integration and XDG
- Use the public `remya_client` and `remya_ui` packages from Remya Core.
- Declare app preferences in `linux/packaging/remya-screen-capture.json` and read/write them only through `AppPreferences('remya-screen-capture')`; remyad owns persistence.
- Keep color history as app-owned XDG state. Provide a desktop `settings` action for Core OpenApp routing.
- Respect `XDG_PICTURES_DIR` in addition to standard XDG base directories.

## Validation
- Regenerate Rust API bindings with `flutter_rust_bridge_codegen` 2.13.0 using `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`. Normalize the output with `cargo fmt --all` and `fvm dart format lib/src/rust_bridge` before reviewing the binding diff. Bundle third-party notices when adding Rust dependencies.

<!-- BEGIN:remya-shared profiles=base,source-length,rust,flutter-app,workstation-install -->
<!-- Generated from remya-apps-skills/rules/. Do not edit manually; run remya-apps-skills/rules/sync.py. -->

## Shared Remya Guidelines

- Write rule documents, including `AGENTS.md`, in English.
- Respect XDG base directories (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`); ignore relative XDG values and use absolute `$HOME` fallbacks; do not create unused cache/state directories. Never automatically modify user Hyprland or desktop configuration.
- License & dependencies: PolyForm Noncommercial License 1.0.0 (`LICENSE`). Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (`MIT`, `BSD`, `Apache-2.0`, `ISC`, `Zlib`, `Unlicense`). Keep `LGPL` libraries dynamically linked or in separate processes; never introduce `GPL`, `AGPL`, `SSPL`, or incompatible strong-copyleft code. Reuse existing helpers/packages.
- Validation hygiene: Keep durable tests for non-trivial logic and regressions; remove obsolete, duplicate, or temporary UI-inspection tests before committing. Validate configuration input, preserve the last valid state on errors, and use atomic persistence.
- Git workflow: Develop and validate on a separate branch `<type>/<short-description>` (lowercase words and hyphens). Use small, focused stacked commits when appropriate. Follow Conventional Commits: `<type>(<scope>): <description>` (lowercase imperative description without a final period; mark breaking changes with `!` or `BREAKING CHANGE:`). Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Inspect diffs, stage only intended paths, and preserve unrelated changes. Commit approval is mandatory: show completed changes and validation results before requesting explicit user approval to run `git commit`. Approval to commit also authorizes merging ready branches into `main`, deleting fully merged local branches (and clean worktrees), pushing `main` to `origin`, and verifying remote refs.

### Source Length Check

- Run `python tool/check_source_length.py` as part of local validation (warns for Rust and Dart files over 800 physical lines, including comments and blank lines). Review every reported file against the single-responsibility principle and refactor files that mix responsibilities.
- When a reviewed file should stay together, run `python tool/check_source_length.py add <path> --reason "<why it should stay together>"` and include the updated `tool/source_length_exceptions.json` (keyed by SHA-256; modified files still over 800 lines require another review).

### Rust Toolchain & Validation

- Use the root `rust-toolchain.toml` (do not change toolchain channels without explicit instruction) and inherit common crate metadata from the workspace where applicable. Commit `Cargo.lock`; ignore build output.
- Run before presenting changes: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`.

### Flutter Linux App Guidelines

- Always invoke Flutter and Dart via `fvm flutter ...` and `fvm dart ...`, never global SDK commands.
- Target Linux only.
- All UI must follow Material Design 3 Expressive (MD3E): import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`; enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Use dot shorthand wherever supported and the expected type is unambiguous. Split complex widgets by responsibility and keep small single-use widgets private.
- Run `fvm flutter pub get` after dependency changes. Run `fvm dart format --output=none --set-exit-if-changed lib test`, `fvm flutter analyze`, `fvm flutter test`, and `fvm flutter build linux --debug` as relevant. Keep debug and release builds sequential because Flutter shares ephemeral native engine files between modes.
- A successful build does not verify desktop behavior; verify affected window behavior and interactions on the real desktop and report untested boundaries.

### Workstation Release Install

- After application or daemon code changes, finish validation, rebuild the release bundle/binaries, and run `python tool/install.py` on this workstation as the final implementation step so the user can manually review the installed application. Source changes and successful builds alone do not complete the task.
- Verify that the installed bundle, command, desktop entry, and any service unit use the updated build, and exercise the installed application. Preserve user configuration and unrelated installations. Install `remya-core` before dependent apps (and Settings before Bar when both change). Stop verification instances you started without disabling persistent user units.
<!-- END:remya-shared -->
