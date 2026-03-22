{
  config,
  pkgs,
  searchModelByRole,
  lib,
  ...
}:

let
  cfg = config.my.home.ai;

  modelInfo = rec {
    worker = {
      model = (searchModelByRole "edit").model;
      provider = (searchModelByRole "edit").provider;
    };
    leader = {
      model = (searchModelByRole "chat").model;
      provider = (searchModelByRole "chat").provider;
    };
    planner = leader;
  };

  goose-cli-wrapped = let
    exportEnvVarStrs = lib.mapAttrsToList (name: value: "export ${name}=${value}") config.my.home.ai.goose.environmentVariables;
    exportEnv = lib.concatStringsSep "\n" exportEnvVarStrs;
  in pkgs.writeShellApplication {
    name = pkgs.goose-cli.meta.mainProgram;
    runtimeInputs = [ pkgs.goose-cli ];
    text = ''
      ${exportEnv}
      exec ${lib.getExe pkgs.goose-cli} "$@"
    '';
  };

  gooseConfig = lib.my.deepMerge {
    GOOSE_PROVIDER = modelInfo.worker.provider;
    GOOSE_MODEL = modelInfo.worker.model;
    GOOSE_LEAD_PROVIDER = modelInfo.leader.provider;
    GOOSE_LEAD_MODEL = modelInfo.leader.model;
    GOOSE_PLANNER_PROVIDER = modelInfo.planner.provider;
    GOOSE_PLANNER_MODEL = modelInfo.planner.model;
    GOOSE_MODE = "auto";
    GOOSE_MAX_TURNS = 1000;
    GOOSE_CLI_MIN_PRIORITY = 0.0;
    GOOSE_CLI_THEME = "dark";
    GOOSE_CLI_SHOW_THINKING = 1;
    GOOSE_RANDOM_THINKING_MESSAGES = false;
    GOOSE_CLI_SHOW_COST = false;
    GOOSE_AUTO_COMPACT_THRESHOLD = 0.8;
    GOOSE_TELEMETRY_ENABLED = false;
    SECURITY_PROMPT_ENABLED = true;
    SECURITY_PROMPT_THRESHOLD = 0.7;

    extensions = {
      developer = {
        bundled = true;
        enabled = true;
        name = "developer";
        timeout = 300;
        type = "builtin";
      };
      memory = {
        bundled = true;
        enabled = true;
        name = "memory";
        timeout = 300;
        type = "builtin";
      };
    };
  } cfg.goose.extraSettings;
in
{
  options.my.home.ai.goose = {
    enable = lib.mkEnableOption "Enable Goose CLI configuration.";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables to set for goose-cli.";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Additional settings for goose-cli.";
    };
  };
  config = lib.mkIf cfg.goose.enable {
    home.packages = with pkgs; [
      goose-cli-wrapped
    ];
    xdg.configFile = {
      "goose/config.yaml.orig".source = lib.my.toYaml gooseConfig;
      "goose/AGENTS.md".text = config.my.home.ai.prompts.instructions."AGENTS.md".text;
    } // lib.optionalAttrs (cfg.providers != null) (
      builtins.listToAttrs (
        map (p: {
          name = "goose/custom_providers/custom_${p.name}.json";
          value = {
            source = lib.my.toYaml {
              name = p.name;
              engine = "openai";
              display_name = p.name;
              description = "Custom ${p.name} provider";
              api_key_env = "${lib.strings.toUpper p.name}_API_KEY";
              base_url = "${p.url}/v1/chat/completions";
              models = map (m: {
                name = m.model;
                # context_limit = m.context_limit or 4096;
              }) p.models;
              headers = p.headers or { };
              supports_streaming = p.supports_streaming or true;
            };
          };
        }) cfg.providers
      )
    );
    # Goose cannot maybe recognize config as symlink.
    home.activation."copy-goose-config" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 644 -D ${config.xdg.configHome}/goose/config.yaml{.orig,}
    '';
  };
}
