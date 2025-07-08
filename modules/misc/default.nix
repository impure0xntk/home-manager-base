{ config, lib, pkgs, ... }:
let
in {

  imports = [
    ./utility.nix
  ];

  home.packages = with pkgs; [
    # TODO: import sh-utils to nix-pkgs
    # sh-utils
  ];

  # manual disable
  manual.manpages.enable = false;
  programs.man.enable = false;
  # news
  # https://github.com/nix-community/home-manager/issues/2033#issuecomment-1848326144
  news = {
    display = "silent";
    json = lib.mkForce { };
    entries = lib.mkForce [ ];
  };
}
