{ pkgs, lib, ... }:
{
  # Shell security
  programs.tirith = {
    enable = true;
    enableFishIntegration = true;
    package = pkgs.stable.tirith; # TODO: switch to unstable after marged https://github.com/NixOS/nixpkgs/pull/562326
  };
}
