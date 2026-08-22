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

  codexWrapProgramArgs =
    let
      envVars = [ "CODEX_HOME ${config.xdg.configHome}/codex" ]
        ++ (lib.optionals cfg.codex.enableCustomProvider [ "${dummyEnvKey} dummy" ]);
    in
    lib.concatStringsSep " " (lib.forEach envVars (envvar: "--set ${envvar}"));
  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";
    version = pkgs.codex.version;
    paths = [ pkgs.codex ];
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex ${codexWrapProgramArgs}
    '';
  };
  codex-acp-wrapped = pkgs.symlinkJoin {
    name = "codex-acp";
    version = pkgs.codex-acp.version;
    paths = [ pkgs.codex-acp ];
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex-acp ${codexWrapProgramArgs}
    '';
  };

  settings = lib.my.deepMerge
    ({
      model_reasoning_effort = "medium";
      hide_agent_reasoning = true;
      approval_policy = "untrusted";
      sandbox_mode = "read-only";
    } //
    (let
      chatModel = searchModelByRole "chat";
    in
    lib.optionalAttrs cfg.codex.enableCustomProvider {
      preferred_auth_method = "apikey";
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
      web_search = "disabled";
    }))
    cfg.codex.extraSettings;

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

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # Resolve model for a profile: look up by role from providers
  resolveModel =
    profileName:
    let
      profile = allProfiles.${profileName};
      found = searchModelByRole profile.model_role;
    in
    if hasCustomModels && found != null then
      found
    else if hasCustomModels then
      let
        firstProvider = builtins.head cfg.providers;
        chatModels = builtins.filter (m: lib.elem "chat" m.roles) firstProvider.models;
      in
      {
        provider = firstProvider.name;
        url = firstProvider.url;
        model = if chatModels != [ ] then (builtins.head chatModels).model else "gpt-5.6-luna";
      }
    else
      null;

  # Build Codex agent TOML entries from ALL abstract profiles
  codexAgentConfigs = lib.mapAttrs (name: profile: {
    inherit name;
    description = profile.description;
    model =
      let m = resolveModel name;
      in lib.optionalString (m != null) m.model;
    model_reasoning_effort = profile.reasoning_effort;
    sandbox_mode = profile.sandbox_mode;
    developer_instructions = profile.instructions;
  }) allProfiles;

  # Only generate when "codex" is listed as a subagent target
  generateCodexAgents = builtins.elem "codex" cfg.subagents.targets;

  configFiles = lib.mapAttrs' (name: profile: {
    name = "codex/${name}.config.toml";
    value.source = lib.my.toToml profile;
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
      default = { };
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
      (lib.optionalAttrs generateCodexAgents (lib.mapAttrs' (name: agentCfg: {
        name = "codex/agents/agent-${name}.toml";
        value.source = lib.my.toToml agentCfg;
      }) codexAgentConfigs))
    ];

    home.activation.fixCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        makeInstallCommands = lib.mapAttrsToList (targetPath: configAttr:
          let
            srcFile = if configAttr ? text then pkgs.writeText (baseNameOf targetPath) configAttr.text else configAttr.source;
          in ''
            install -D -m 644 "${srcFile}" "${config.xdg.configHome}/${targetPath}"
          ''
        ) configFiles;
      in
      lib.concatStringsSep "\n" makeInstallCommands
    );
  };
}
