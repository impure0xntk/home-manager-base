{ config, lib, pkgs, searchModelByRole, ... }:
let
  cfg = config.my.home.ai.orchestration.omnigent;

  commonMetaAgentSetting = {
    spec_version = 1;
  };

  generateRunnerSettings = { harness, modelRole, prompt, extra ? {},}: {
    inherit prompt;
    executor = {
      type = "omnigent";
      config = {
        inherit harness;
        model = (searchModelByRole modelRole).model;
      };
    };
    os_env = {
      type = "caller_process";
      cwd = ".";
      sandbox.type = "none";
    };
  } // extra;

  defaultMetaAgentSettings = with config.my.home.ai.subagents; {
    planner-worker = (generateRunnerSettings {
      harness = "codex-native";
      modelRole = profiles.planner.model_role;
      prompt = profiles.planner.instructions;
    }) // {
      async = true;
      cancellable = true;
      tools = {
        worker = generateRunnerSettings {
          harness = "codex-native";
          modelRole = profiles.worker.model_role;
          prompt = profiles.worker.instructions;
          extra = {
            type = "agent";
            pass_history = true;
          };
        };
        reviewer = generateRunnerSettings {
          harness = "codex-native";
          modelRole = profiles.reviewer.model_role;
          prompt = profiles.reviewer.instructions;
          extra = {
            type = "agent";
            pass_history = true;
          };
        };
      };
    };
  };
in
{
  options.my.home.ai.orchestration = {
    omnigent = with lib; {
      enable = mkEnableOption "Omnigent orchestration platform";
      package = mkOption {
        type = lib.types.package;
        default = pkgs.my.omnigent;
        description = "Omnigent package to use";
      };
      settings = mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Omnigent configuration settings (merged into config.yaml)";
      };
      metaAgentSettings = mkOption {
        type = types.attrs;
        default = defaultMetaAgentSettings;
        description = "Omnigent meta-agent settings";
        example = {
          planner-worker = {
            executor = {
              type = "omnigent";
              config = {
                harness = "codex-native";
              };
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ] ++ [
    ];

    # Set OMNIGENT_CONFIG_HOME to XDG config directory
    # Omnigent recognizes this as the parent directory for config.yaml
    home.sessionVariables = {
      OMNIGENT_CONFIG_HOME = "${config.xdg.configHome}/omnigent";
      OMNIGENT_DATA_DIR = "${config.xdg.dataHome}/omnigent";
    };

    # Create XDG config directory for Omnigent
    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: setting: {
        name = "omnigent/meta-agents/${name}/config.yaml";
        value.source = lib.my.toYaml (commonMetaAgentSetting // { inherit name; } // setting);
      }) cfg.metaAgentSettings)
      {
        "omnigent/config.yaml".source = lib.my.toYaml ({
          harness = {
            codex-native = lib.optionalAttrs config.my.home.ai.codex.enable {
              command = lib.getExe config.programs.codex.package;
              args = "--profile workspace_auto --sandbox danger-full-access";
            };
          };
          providers = {
            litellm = {
              kind = "cli-config";
              cli = "codex";
              model_provider = "custom-litellm";
              default = "openai";
            };
          };

          # Default Omnigent configuration
          logging = {
            level = "info";
            format = "json";
          };
        } // cfg.settings);
      }
    ];

    # Materialize Omnigent agent bundles so that they contain regular files
    # instead of symlinks into the Nix store.
    home.activation.omnigentBundles =
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        bundle_dir="${config.xdg.dataHome}/omnigent"

        rm -rf "$bundle_dir"
        mkdir -p "$bundle_dir"

        cp -aL \
          "${config.xdg.configHome}/omnigent/meta-agents" \
          "$bundle_dir/"
      '';
  };
}
