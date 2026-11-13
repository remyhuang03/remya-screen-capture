# Contributing to Remy'a Screen Capture

Bug reports, documentation fixes, tests, and code contributions are welcome.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Report a problem or suggest a change

Search [existing issues](https://github.com/remyhuang03/remya-screen-capture/issues?q=is%3Aissue)
first, then [choose an issue template](https://github.com/remyhuang03/remya-screen-capture/issues/new/choose).
For a large feature or a change to capture behavior, open an issue first so we
can agree on scope. Report vulnerabilities through the
[security policy](SECURITY.md).

## Set up and make a change

1. Fork the repository and start a topic branch from `main`, for example
   `fix/region-selection` or `docs/installation`.
2. Follow the [development setup](README.md#-development). Use the Flutter SDK
   pinned in `.fvmrc` via FVM, the Rust toolchain pinned in `rust-toolchain.toml`,
   and a sibling `remya-core` checkout for `remya_client` and `remya_ui`.
3. Keep the pull request focused. Follow the [project guidelines](AGENTS.md) for
   architecture, accessible UI, and regenerating Rust bridge bindings when the
   bridge API changes. Add a regression test for non-trivial fixes when practical.
4. Use Conventional Commits, for example
   `fix(screenshot): preserve the selected monitor`.
5. Open a pull request against `main`. Describe the change, link relevant
   issues, and record validation results.

## Verify your change

Run the checks relevant to the files you changed:

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

For capture, recording, or input changes, test the affected flow in a real
Hyprland session when possible. Record the monitor, GPU, or audio setup when
it affects the result, and state any scenarios you could not verify. Share
only sanitized logs and media.

See [LICENSE](LICENSE) for the project's PolyForm Noncommercial License 1.0.0.
When adding dependencies or assets, verify license compatibility and preserve
required notices.
