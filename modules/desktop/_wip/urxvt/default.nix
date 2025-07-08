{ config, pkgs, lib, systemConfig, ... }:
let
  urxvtPatched = pkgs.rxvt-unicode-unwrapped.overrideAttrs (final: prev: {
    patches = [
      # Bug with tmux:
      # https://github.com/tmux/tmux/issues/3852#issuecomment-1962934068
      # https://gitlab.archlinux.org/archlinux/packaging/packages/rxvt-unicode/-/issues/2
      (pkgs.fetchurl {
        url = "https://github.com/exg/rxvt-unicode/commit/417b540d6dba67d440e3617bc2cf6d7cea1ed968.diff";
        hash = "sha256-ja++UQ+Aw2vlyRd3mRtrkG/y+TZEYtmQJwvSkJs5W0Y=";
      })
    ] ++ (prev.patches or []);
  });
  urxvtWrapped = pkgs.writeShellApplication {
    name = "urxvt";
    runtimeInputs = [urxvtPatched];
    text = ''
      set +e
      ${urxvtPatched}/bin/urxvtc -e "${pkgs.runtimeShell}" "$@"
      if [ $? -eq 2 ]; then
        ${urxvtPatched}/bin/urxvtd -q -o -f
        ${urxvtPatched}/bin/urxvtc -e "${pkgs.runtimeShell}" "$@"
      fi
      '';
  };
in {
  # http://malkalech.com/urxvt_terminal_emulator
  programs.urxvt = {
    enable = true;
    package = urxvtWrapped;
    transparent = true;
    shading = 100;
    fonts = [
      "xft:Noto Sans Mono CJK JP:pixelsize=14:antialias=true:hinting=true"
    ];
    scroll.bar.enable = false;
    iso14755 = false; # disable popup when pressing Ctrl+Shift+<any>
    extraConfig = {
      # For fully transparency. needs composit manager like compton
      depth = 32;
      background = "rgba:0000/0000/0200/c800";

      geometry = "96x32";
      visualBell = true;
      saveLines = 3000;
      fading = 40;

      letterSpace = -3;

      # Disable perl ext
      perl-ext = "";
      perl-ext-common = "";
    };
  };
  services.picom.opacityRules = [
    "80:class_g = 'URxvt'"
  ];
}
