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
    planner = {
      model = (searchModelByRole "chat").model;
      provider = (searchModelByRole "chat").provider;
    };
  };

  goose-cli-wrapped =
    let
      exportEnvVarStrs = lib.mapAttrsToList (name: value: "export ${name}=${value}") config.my.home.ai.goose.environmentVariables;
      exportEnv = lib.concatStringsSep "\n" exportEnvVarStrs;
    in
    pkgs.writeShellApplication {
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

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # Generate Goose Recipes (YAML) from abstract profiles
  # Goose recipes define reusable sub-agent configurations referenced by name.
  # See: https://goose-docs.ai/docs/guides/context-engineering/subagents/
  gooseRecipes = lib.mapAttrs (name: profile:
    let
      model = searchModelByRole profile.model_role;
      id = "subagent-${name}";
    in
    {
      inherit id;
      version = "1.0.0";
      title = id;
      description = profile.description;
      instructions = profile.instructions;
      activities = [ profile.model_role ];
      prompt = profile.instructions;
      parameters = [
        {
          key = "sandbox_mode";
          input_type = "string";
          requirement = "optional";
          default = profile.sandbox_mode;
        }
        {
          key = "reasoning_effort";
          input_type = "string";
          requirement = "optional";
          default = profile.reasoning_effort;
        }
      ];
      model = if model != null then model.model else null;
      temperature = if profile.reasoning_effort == "high" then 0.1 else if profile.reasoning_effort == "low" then 0.3 else 0.2;
    }
  ) allProfiles;

  # Only generate when "goose" is listed as a subagent target
  generateGooseRecipes = builtins.elem "goose" cfg.subagents.targets;
in
{
  options.my.home.ai.goose = {
    enable = lib.mkEnableOption "Enable Goose CLI configuration.";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables to set for goose-cli.";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional settings for goose-cli.";
    };
  };
  config = lib.mkIf cfg.goose.enable {
    home.packages = with pkgs; [
      goose-cli-wrapped
    ];
    xdg.configFile = lib.mkMerge [
      {
        "goose/config.yaml.orig".source = lib.my.toYaml gooseConfig;
        "goose/AGENTS.md".source = config.my.home.ai.prompts.instructions."AGENTS.md".source;
      }
      (lib.optionalAttrs generateGooseRecipes (lib.mapAttrs' (name: recipe: {
        name = "goose/recipes/subagent-${name}.yaml";
        value.source = lib.my.toYaml recipe;
      }) gooseRecipes))
      (lib.optionalAttrs (cfg.providers != null) (
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
                }) p.models;
                headers = p.headers or { };
                supports_streaming = p.supports_streaming or true;
              };
            };
          }) cfg.providers
        )
      ))
    ];
    # Goose cannot recognize config as symlink.
    home.activation."copy-goose-config" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 644 -D ${config.xdg.configHome}/goose/config.yaml{.orig,}
    '';
  };
}
