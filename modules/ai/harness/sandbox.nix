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
        filesystem = {
          allowWrite = ["." "/tmp"];
        };
      };
    };
  };

  # Fence masks a whole executable path for a runtime deny, so denying one
  # coreutils command such as `chroot` would also block `cat`, `head` and every
  # other alias sharing the same binary. Accepting every coreutils command
  # keeps the deny rule preflight-only instead of masking the shared binary.
  # Both variants ship because PATH inside the sandbox may pick either one.
  coreutilsCommands = lib.unique (
    lib.concatMap
      (pkg: builtins.attrNames (builtins.readDir "${pkg}/bin"))
      [ pkgs.coreutils-full ]
  );

  # Baseline every profile gets: the Nix-provided binaries must stay readable
  # and runnable inside the sandbox.
  settingsForNixEnv = {
    "$schema" = "https://raw.githubusercontent.com/fencesandbox/fence/main/docs/schema/fence.schema.json";
    filesystem = {
      allowRead = ["/nix/store"];
      allowExecute = ["/nix/store"];
    };
    command.acceptSharedBinaryCannotRuntimeDeny = coreutilsCommands;
  };

  finalProfiles = lib.mapAttrs' (name: entry: {
    inherit name;
    value = lib.my.deepMerge entry { settings = settingsForNixEnv; };
  }) cfg.harness.sandbox.profiles;

  defaultProfileNames = lib.attrNames (lib.filterAttrs (_name: entry: entry.default) finalProfiles);
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
          default = mkEnableOption ''
            Whether to use this profile as the default profile of the AI
            harness sandbox. Its settings become `fence/fence.json`, the config
            Fence loads when it finds no project-local config. At most one
            profile may set this.
          '';
        };
      });
      default = defaultProfiles;
      description = ''
        Fence sandbox profiles. Each profile is written to
        `fence/<name>.json`, and the single profile with `default = true` is
        copied to `fence/fence.json`, the config Fence loads when it finds no
        project-local config. Without one, `fence/fence.json` is not written.
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
      (lib.optionalAttrs (defaultProfileNames != [ ]) {
        "fence/fence.json".text = builtins.toJSON finalProfiles.${lib.head defaultProfileNames}.settings + "\n";
      })
    ];

    assertions = [
      {
        assertion = builtins.length defaultProfileNames <= 1;
        message = "my.home.ai.harness.sandbox.profiles: at most one profile may set default = true, but found: ${lib.concatStringsSep ", " defaultProfileNames}";
      }
    ];
  };
}
