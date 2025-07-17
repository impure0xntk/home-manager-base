{ pkgs, lib, system, self, home-manager, }:
let
in {
  my.home.ide.jetbrains-remote = {
    enable = true;
    ides = with pkgs.jetbrains; [idea-community-bin];
  };
}
