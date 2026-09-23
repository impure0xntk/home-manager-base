{config, pkgs, lib, ...}:
{
  home.packages = with pkgs; [
    # beads-rust
    # beads-viewer
    # gnhf
    # (my.cli-agent-orchestrator.override {
    #   tmux = config.programs.tmux.package;
    # })
  ];
}
