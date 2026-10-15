{config, pkgs, lib, ...}:
let
  shellAliases = {
    ms = "multistack --no-worktree";
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
    my.multistack
  ];

  programs.bash.shellAliases = shellAliases;
  programs.fish.shellAbbrs = shellAliases;

}
