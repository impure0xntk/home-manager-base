{ pkgs, lib, ... }:
{
  # Shell security
  programs.tirith = {
    enable = true;
    enableFishIntegration = true;
    package = pkgs.unstable.tirith;
  };
}
