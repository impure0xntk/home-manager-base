{config, pkgs, lib, ...}:
let
  shellAliases = {
    ms = "multistack --no-worktree";
  };
  agent-manager = pkgs.agent-manager.override {
    tmux = config.programs.tmux.package;
  };

  settingsFile = pkgs.writeText "settings.json" (builtins.toJSON {
    version = 1;
    settings = {
      "keybindings.session" = ''{"review":[]}''; # original: ctrl+r
    };
  });
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

  # Apply agent-manager settings
  home.activation.importAgentManagerSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${lib.getExe agent-manager} import "${settingsFile}"
  '';

  programs.bash.shellAliases = shellAliases;
  programs.fish.shellAbbrs = shellAliases;

}
