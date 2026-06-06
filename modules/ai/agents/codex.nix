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
  codexWrapProgramArgs = let
    envVars = ["CODEX_HOME ${config.xdg.configHome}/codex"]
      ++ (lib.optionals cfg.codex.enableCustomProvider ["${dummyEnvKey} dummy"]);
  in 
    lib.concatStringsSep " "
      (lib.forEach envVars (envvar: "--set ${envvar}"));
  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";
    version = pkgs.codex.version;

    paths = [
      pkgs.codex
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/codex ${codexWrapProgramArgs}
    '';
  };
  codex-acp-wrapped = pkgs.symlinkJoin {
    name = "codex-acp";
    version = pkgs.codex-acp.version;

    paths = [
      pkgs.codex-acp
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/codex-acp ${codexWrapProgramArgs}
    '';
  };

  settings = lib.my.deepMerge ({
    model_reasoning_effort = "high";
    hide_agent_reasoning = true;

    # policy: strict
    approval_policy = "untrusted";
    sandbox_mode = "read-only";
  } // (let
    chatModel = searchModelByRole "chat";
  in lib.optionalAttrs cfg.codex.enableCustomProvider {
    preferred_auth_method = "apikey";
    # model/provider
    model = chatModel.model;
    model_provider = "custom-${chatModel.provider}";
    model_providers = builtins.listToAttrs (
      builtins.map (provider: {
        name = "custom-${provider.name}";
        value = {
          name = provider.name;
          base_url = "${provider.url}";
          env_key = dummyEnvKey;
        };
      }) cfg.providers
    );

    web_search = "disabled"; # To reduce search cost
  })) cfg.codex.extraSettings;

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

  hasCustomModels = cfg.codex.enableCustomProvider && cfg.providers != null;
  codexModels = lib.listToAttrs (lib.forEach ["gpt-5.4" "gpt-5.4-mini"] (modelName: {
    name = modelName;
    value = {
      provider = null;
      url = null;
      model = modelName;
      roles = [];
    };
  }));
  models = if hasCustomModels then rec {
    planner = searchModelByRole "chat";
    worker = searchModelByRole "edit";
    reviewer = planner;
  } else rec {
    planner = codexModels."gpt-5.4";
    worker = codexModels."gpt-5.4-mini";
    reviewer = planner;
  };

  agents = {
    planner = {
      name = "planner";
      description = "Planner agent";
      model = models.planner.model;
      model_reasoning_effort = "high";
      sandbox_mode = "read-only";
      developer_instructions = ''
      You are the plan agent.
      You analyze the task, create detailed plans, and assign work to workers.
      '';
    };
    worker = {
      name = "worker";
      description = "Worker agent";
      model = models.worker.model;
      model_reasoning_effort = "low";
      developer_instructions = ''
      You are the worker agent.
      You execute the plan from the plan agent, write code, and verify results.
      '';
    };
    reviewer = {
      name = "reviewer";
      description = "PR reviewer focused on correctness, security, and missing tests.";
      model = models.planner.model;
      model_reasoning_effort = "high";
      sandbox_mode = "read-only";
      developer_instructions = ''
      Review code like an owner.
      Prioritize correctness, security, behavior regressions, and missing test coverage.
      Lead with concrete findings, include reproduction steps when possible, and avoid style-only comments unless they hide a real bug.
      '';
    };
  };

  configFiles = lib.mapAttrs' (name: profile: {
    name = "codex/${name}.config.toml";
    value = {
      source = lib.my.toToml profile;
    };
  }) profiles;

  shellAliases = {
    cx = "codex";
  };
in
{
  options.my.home.ai.codex = {
    enable = lib.mkEnableOption "Enable Codex agent";
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
      context = builtins.readFile config.my.home.ai.prompts.instructions."AGENTS.md".source;
      inherit settings;
    };

    home.packages = [ codex-acp-wrapped ];

    programs = {
      bash.shellAliases = shellAliases;
      fish.shellAbbrs = shellAliases;
    };

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (name: agent: {
        name = "codex/agents/agent-${name}.toml";
        value = {
          source = lib.my.toToml agent;
        };
      }) agents)
    ];

    # Config file that includes profile info must be writable for trust directory adding
    home.activation.fixCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    let
      makeInstallCommands = lib.mapAttrsToList (targetPath: configAttr:
        let
          srcFile = if configAttr ? text then pkgs.writeText (baseNameOf targetPath) configAttr.text else configAttr.source;
        in
        ''
          install -D -m 644 "${srcFile}" "${config.xdg.configHome}/${targetPath}"
        ''
      ) configFiles;
    in lib.concatStringsSep "\n" makeInstallCommands);
  };
}
