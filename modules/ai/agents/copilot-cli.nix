{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  # Create a wrapped version of the "copilot-cli" package.
  # This forces $COPILOT_HOME to always point to $XDG_CONFIG_DIRECTORY.
  # See: https://github.com/github/copilot-cli/issues/1750
  copilot-cli-wrapped = pkgs.symlinkJoin {
    name = "copilot-cli";
    version = pkgs.copilot-cli.version;

    paths = [
      pkgs.copilot-cli
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/copilot \
        --set COPILOT_HOME ${config.xdg.configHome}/copilot
    '';
  };

  settings = lib.my.deepMerge {
    autoUpdate = false;
    banner = "never";

    includeCoAuthoredBy = false;
    # skillDirectories = [ config.my.home.ai.openskills.];

    effortLevel = "high";
  } cfg.codex.extraSettings;
in
{
  options.my.home.ai.copilot-cli = {
    enable = lib.mkEnableOption "Enable Copilot CLI agent";
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Copilot CLI agent settings";
    };
  };
  config = lib.mkIf cfg.copilot-cli.enable {
    # TODO: refactor after home-manager 26.05
    home.packages = [ copilot-cli-wrapped ];

    xdg.configFile = {
      "copilot/settings.json".text = builtins.toJSON settings;
    };
  };
}
