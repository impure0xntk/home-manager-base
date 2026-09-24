{
  config,
  pkgs,
  searchModelByRole,
  lib,
  ...
}:

let
  cfg = config.my.home.ai;

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

  chatProvider = searchModelByRole "chat";

  gooseConfig = lib.my.deepMerge {
    GOOSE_MODE = "auto";
    GOOSE_MAX_TURNS = 1000;
    GOOSE_CLI_MIN_PRIORITY = 0.8; # High: low verbosity
    GOOSE_MAX_CODE_BLOCK_LINES = 20;
    GOOSE_TRUNCATED_SHOW_LINES = 10;
    GOOSE_CLI_THEME = "dark";
    GOOSE_CLI_SHOW_THINKING = 1;
    GOOSE_RANDOM_THINKING_MESSAGES = false;
    GOOSE_CLI_SHOW_COST = false;
    GOOSE_AUTO_COMPACT_THRESHOLD = 0.8;
    GOOSE_TELEMETRY_ENABLED = false;
    SECURITY_PROMPT_ENABLED = true;
    SECURITY_PROMPT_THRESHOLD = 0.7;

    active_provider = chatProvider.provider;
    providers.${chatProvider.provider} = {
      enabled = true;
      model = chatProvider.model;
      configured = true;
    };

    GOOSE_RECIPE_PATH = "${config.xdg.configHome}/goose/recipes";

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
      id = name;
    in
    {
      inherit id;
      version = "1.0.0";
      title = id;
      description = profile.description;
      instructions = profile.instructions;
      # activities = [ profile.model_role ];
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

  # Skills directory:
  # Goose discovers skills from ~/.agents/skills/ (recommended), .goose/skills/, .claude/skills/, ~/.claude/skills/
  # my.home.ai.harness.skills sets to ~/.agents/skills so no need to set by goose.
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
      }
      (lib.optionalAttrs generateGooseRecipes (lib.mapAttrs' (name: recipe: {
        name = "goose/recipes/${name}.yaml";
        value.source = lib.my.toYaml recipe;
      }) gooseRecipes))
      (lib.optionalAttrs (cfg.providers != null) (
        builtins.listToAttrs (
          map (p: {
            name = "goose/custom_providers/custom_${p.name}.json";
            value = {
              text = builtins.toJSON {
                name = p.name;
                engine = "openai";
                display_name = p.name;
                description = "Custom ${p.name} provider";
                api_key_env = p.api-key-env;
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
    # And Goose cannot read AGENTS.md, read only .goosehints
    home.activation."copy-goose-config" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 644 -D ${config.xdg.configHome}/goose/config.yaml{.orig,}
      install -m 644 -D ${config.my.home.ai.harness.agentsMd.source} ${config.xdg.configHome}/goose/.goosehints
    '';
    programs.fish.interactiveShellInit = ''
      goose completion fish | source
    '';
  };
}
