{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  defaultProfiles = {
    default = {
      default = true;
      settings = {
        # network = {
        #   allowLocalOutbound = true;
        # };
        filesystem = {
          allowWrite = ["." "/tmp"];
        };
      };
    };
  };

  # Baseline every profile gets: the Nix-provided binaries must stay readable
  # and runnable inside the sandbox.
  settingsForNixEnv = {
    "$schema" = "https://raw.githubusercontent.com/fencesandbox/fence/main/docs/schema/fence.schema.json";
    filesystem = {
      allowRead = ["/nix/store"];
      allowExecute = ["/nix/store"];
    };
  };

  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = lib.my.deepMerge entry { settings = settingsForNixEnv; };
  }) cfg.harness.sandbox.profiles;

  # Profiles flagged `default` compose the user config Fence auto-loads from
  # $XDG_CONFIG_HOME/fence/fence.json. Several defaults are deep-merged, and
  # attrsOf iterates in name order, so the result stays deterministic.
  defaultSettings = lib.foldl'
    (acc: entry: lib.my.deepMerge acc entry.settings)
    { }
    (lib.attrValues (lib.filterAttrs (_name: entry: entry.default) finalProfiles));
in
{
  options.my.home.ai.harness.sandbox = with lib; with lib.types; {
    enable = mkEnableOption "Whether to enable the AI harness sandbox";
    profiles = mkOption {
      type = attrsOf (submodule {
        options = {
          settings = mkOption {
            type = attrs;
            description = ''
              Settings for the sandbox profile, merged with the settings every
              profile needs (schema URL and /nix/store access). Rendered as
              JSON for Fence, see
              https://github.com/fencesandbox/fence/blob/main/docs/configuration.md
            '';
          };
          default = mkEnableOption "Whether to use this profile as the default profile (fence.json) for the AI harness sandbox.";
        };
      });
      default = defaultProfiles;
      description = ''
        Fence sandbox profiles. Each profile is written to
        `fence/<name>.json`, and the profiles with `default = true` are merged
        into `fence/fence.json`, the config Fence loads when it finds no
        project-local config.
      '';
    };
  };
  config = lib.mkIf (cfg.harness.enable && cfg.harness.sandbox.enable) {
    home.packages = with pkgs; [
      fence
    ];

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: entry: {
        name = "fence/${name}.json";
        value.text = builtins.toJSON entry.settings + "\n";
      }) finalProfiles)
      (lib.optionalAttrs (defaultSettings != { }) {
        "fence/fence.json".text = builtins.toJSON defaultSettings + "\n";
      })
    ];
  };
}
