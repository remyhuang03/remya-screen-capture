{ pkgs ? import <nixpkgs> { } }:
import ../remya-core/nix/flutter-shell.nix {
  inherit pkgs;
  extraPackages = pkgs: with pkgs; [
    ffmpeg
    grim
    gtk-layer-shell
    libass
    libunwind
    mpv-unwrapped
    wayland
    wayland-protocols
    wayland-scanner
    wl-clipboard
    xdg-utils
  ];
}
