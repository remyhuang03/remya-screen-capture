# Agent Instructions & Development Guidelines

## Project Scope
- `remya_screen_capture` is a screen capture tool for Hyprland on Linux, using Flutter and Rust.
- The project provides screen, window, and region capture with Material Design 3 Expressive UI and native Rust performance backends.
- Application ID is `top.remya.screen_capture`. The executable is `remya_screen_capture`.
- Add real capture behavior and platform integrations only when required by a concrete task.
- Never present sample values as detected system state or claim an integration works merely because its UI renders.
- Write rule documents, including `AGENTS.md`, in English.

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
- Respect XDG base directory specifications (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_PICTURES_DIR`). Do not create unused cache/state directories.

## Toolchains & Dependencies
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.9` (latest stable). Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` and inherit common crate metadata from the workspace.
- Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
- Reuse existing helpers and dependencies. Add packages only for concrete requirements.
- Prefer existing packages and platform libraries over implementing equivalent behavior.
- This project uses the PolyForm Noncommercial License 1.0.0 (`LICENSE`), matching `remya_bar` and `remya_settings`.
- Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (MIT, BSD, Apache-2.0, ISC, Zlib, Unlicense).

## Coding & UI
- All UI must follow Material Design 3 Expressive (MD3E).
- Import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`.
- Use dot shorthand wherever supported and the expected type is unambiguous. Keep explicit types when shorthand cannot resolve correctly.
- Split complex components into smaller objects with clear responsibilities.
- Preserve keyboard navigation, visible focus, readable contrast, and accessibility.
- Target Linux only; do not generate other platforms without explicit instruction.

## Validation
- Run relevant checks before presenting changes for review:
  ```bash
  fvm dart format --output=none --set-exit-if-changed lib test
  fvm flutter analyze
  fvm flutter test
  fvm flutter build linux --debug
  cargo fmt --all -- --check
  cargo clippy --workspace --all-targets -- -D warnings
  cargo test --workspace
  git diff --check
  ```
- Run `fvm flutter pub get` after dependency changes.
- Once Rust APIs exist, regenerate bridge bindings after API changes and run `cargo fmt --all`. Bundle third-party notices when adding Rust dependencies.
- Keep durable tests for non-trivial logic and regressions.

## Git Workflow
- Develop and validate on a separate branch using `<type>/<short-description>` with lowercase words and hyphens.
- Follow Conventional Commits: `<type>(<scope>): <description>`. Use a lowercase imperative description without a final period; mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`.
- Inspect diffs, stage only intended paths, and preserve unrelated changes.
- Commit approval is mandatory: show completed changes and validation results before requesting explicit user review approval to run `git commit`.
- Approval to commit also authorizes delivery of the approved work. Merge each ready branch into `main`, push `main` to `origin`, and verify the remote ref after delivery. Remove delivered local branches and their clean worktrees once they are fully merged. Obtain approval before merging or pushing.
