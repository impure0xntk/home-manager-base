{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;

  dummyEnvKey = "OPENAI_API_KEY"; # just-every/code allows only OPENAI_API_KEY

  # Create a wrapped version of the "codex" package.
  # This forces $CODEX_HOME to always point to $XDG_CONFIG_DIRECTORY.
  # See: https://github.com/openai/codex/issues/1980
  #
  # And integrate to litellm.
  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";
    version = pkgs.codex.version;

    paths = if cfg.codex.enableJustEveryCode then [
      pkgs.code # just-every/code: codex alternative
    ] else [
      pkgs.codex
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    postBuild = (if cfg.codex.enableJustEveryCode then ''
      makeWrapper $out/bin/code $out/bin/codex \
    '' else ''
      wrapProgram $out/bin/codex \
    '') + ''
        --set ${dummyEnvKey} dummy
    '';
  };

  codex-acp = pkgs.writeShellScriptBin "codex-acp" (
    if cfg.codex.enableJustEveryCode then
    "exec ${lib.getExe config.programs.codex.package} mcp-server"
    else
    "exec ${lib.getExe pkgs.codex-acp}"
  );

  settings = lib.my.deepMerge ({
      model_reasoning_effort = "high";
      hide_agent_reasoning = true;

      # policy: strict
      approval_policy = "untrusted";
      sandbox_mode = "read-only";

      profiles = {
        full_auto = {
          approval_policy = "on-request";
          sandbox_mode = "workspace-write";
        };
        readonly_quiet = {
          approval_policy = "never";
          sandbox_mode = "read-only";
        };
      };
    } // (let
      chatModel = searchModelByRole "chat";
    in lib.optionalAttrs cfg.codex.enableCustomProvider {
      preferred_auth_method = "apikey";
      # model/provider
      model = chatModel.model;
      model_provider = chatModel.provider;
      model_providers = builtins.listToAttrs (
        builtins.map (provider: {
          name = provider.name;
          value = {
            name = provider.name;
            base_url = "${provider.url}";
            env_key = dummyEnvKey;
          };
        }) cfg.providers
      );
    }) // (lib.optionalAttrs cfg.codex.enableJustEveryCode {
      tui = {
        theme.name = "dark-zen-garden";
        spinner.name = "brailleDotsClassic";
      };
    })) cfg.codex.extraSettings;

  shellAliases = {
    cx = "codex";
  };
in
{
  options.my.home.ai.codex = {
    enable = lib.mkEnableOption "Enable Codex agent";
    enableJustEveryCode = lib.mkEnableOption "Enable just-every/code as codex provider";
    enableCustomProvider = lib.mkEnableOption "Enable custom provider configuration";
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Codex agent settings";
    };
  };
  config = lib.mkIf cfg.codex.enable {
    programs.codex = {
      enable = true;
      package = codex-wrapped;
      custom-instructions = config.my.home.ai.prompts.instructions."AGENTS.md".text;
      inherit settings;
    };

    home.packages = [ codex-acp ];

    programs = {
      bash.shellAliases = shellAliases;
      fish.shellAbbrs = shellAliases;
    };

    xdg.configFile = let
      multiModels = {
        plan = searchModelByRole "chat";
        worker = searchModelByRole "edit";
      };
    in lib.optionalAttrs (cfg.codex.enableCustomProvider && cfg.providers != null) {
      "codex/agents/planner.toml".source = lib.my.toToml {
        description = "Planner agent";
        model = multiModels.plan.model;
        model_reasoning_effort = "high";
        developer_instructions = "You are the plan agent. You analyze the task, create detailed plans, and assign work to workers.";
      };
      "codex/agents/worker.toml".source = lib.my.toToml {
        description = "Worker agent";
        model = multiModels.worker.model;
        model_reasoning_effort = "low";
        developer_instructions = "You are the worker agent. You execute the plan from the plan agent, write code, and verify results.";
      };
    };
  };
}
