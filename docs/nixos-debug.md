# Debug on NixOS

Keep the Remya Core NixOS checkout at `../remya-core`. Capture uses its Dart
packages and the shared Flutter development shell. In the guest's Hyprland
session, follow the Core graphical-session setup to export the isolated XDG
directories and start `remyad` in a separate terminal.
[Core NixOS development guide](../../remya-core/docs/nixos-debug.md)

Open the shell and export the same XDG directories in the Capture terminal. Stage
the app registration in the shared debug data directory before opening settings.

```sh
nix-shell -I nixpkgs=channel:nixos-unstable
```

```sh
install -Dm644 linux/packaging/remya-screen-capture.json \
  "${XDG_DATA_HOME:?export the debug data directory from Core's guide}/remya/apps/remya-screen-capture.json"
fvm install --skip-pub-get
fvm flutter pub get --enforce-lockfile
fvm flutter build linux --debug --no-pub
```

Launch the bundle from the same shell and try a region screenshot, the color
picker and the settings window. Save screenshots into a temporary directory.

```sh
capture=./build/linux/x64/debug/bundle/remya_screen_capture
"$capture"
"$capture" --color-picker
"$capture" --settings
```

Recording also requires a working `gpu-screen-recorder` command and a supported
GPU and driver. Verify recording separately on the guest if it exposes working
hardware video encoding. The debug shell provides FFmpeg and libmpv for export
and preview.
