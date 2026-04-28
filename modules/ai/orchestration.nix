{config, pkgs, lib, ...}:
{
  home.packages = with pkgs; [
    # beads-rust
    # beads-viewer
  ];
}