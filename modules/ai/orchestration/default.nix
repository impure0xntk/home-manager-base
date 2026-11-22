{config, pkgs, lib, ...}:
let
  shellAliases = {
    ms = "multistack --no-worktree";
  };
  agent-manager = pkgs.agent-manager.override {
    tmux = config.programs.tmux.package;
  };
in
{
  home.packages = with pkgs; [
    # beads-rust
    # beads-viewer
    # gnhf
    # (my.cli-agent-orchestrator.override {
    #   tmux = config.programs.tmux.package;
    # })
    # my.multistack
    agent-manager
  ];

  programs.bash.shellAliases = shellAliases;
  programs.fish.shellAbbrs = shellAliases;

}
