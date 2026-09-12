# Use specific profile except not for the default one.
#   By default, codex try to write settings to config.yaml and fail because the config.yaml is readonly.
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

  # Build package list and environment variables for codex wrapper
  toolPackages = lib.mapAttrsToList (name: tool: tool.package) cfg.harness.codingAgentTools;
  toolEnvVars = lib.concatMap (tool: lib.mapAttrsToList (name: value: "${name} ${value}") tool.envVars) (builtins.attrValues cfg.harness.codingAgentTools);

  codexWrapProgramArgs =
    let
      envVars = [
        "CODEX_HOME ${config.xdg.configHome}/codex"
      ]
        ++ (lib.optionals cfg.codex.enableCustomProvider [ "${dummyEnvKey} dummy" ])
        ++ toolEnvVars;
    in
    lib.concatStringsSep " " (lib.forEach envVars (envvar: "--set ${envvar}"));

  codex-wrapped = pkgs.symlinkJoin {
    name = "codex";
    version = pkgs.codex.version;
    paths = [ pkgs.codex ] ++ toolPackages;
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex ${codexWrapProgramArgs}
    '';
  };
  codex-acp-wrapped = pkgs.symlinkJoin {
    name = "codex-acp";
    version = pkgs.codex-acp.version;
    paths = [ pkgs.codex-acp ] ++ toolPackages;
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex-acp ${codexWrapProgramArgs}
    '';
  };

  settings = lib.my.deepMerge
    ({
      model_reasoning_effort = "medium";
      hide_agent_reasoning = true;
      approval_policy = "on-request";
      sandbox_mode = "read-only";

      agents = {
        max_threads = 4;
        max_depth = 1;
      } // subagentConfigFiles;
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
    global_auto = {
      approval_policy = "on-request";
      sandbox_mode = "danger-full-access";
      network_access = true;
    };
    workspace_auto = {
      approval_policy = "on-request";
      sandbox_mode = "workspace-write";
      network_access = true;
    };
    readonly_quiet = {
      approval_policy = "never";
      sandbox_mode = "read-only";
      network_access = true;
    };
  };

  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  generateCodexAgents = cfg.subagents.enable && builtins.elem "codex" cfg.subagents.targets;

  # https://github.com/openai/codex/issues/19399#issuecomment-[PHONE]
  subagentConfigFiles = lib.optionalAttrs generateCodexAgents (
    lib.mapAttrs (name: _profile: {
      config_file = "agents/${name}.toml";
    }) allProfiles
  );

  codexAgentConfigs = lib.mapAttrs (
    name: profile:
    let
      resolvedModel = searchModelByRole profile.model_role;
    in
    {
      inherit name;
      description = profile.description;
      model_reasoning_effort = profile.reasoning_effort;
      sandbox_mode = profile.sandbox_mode;
      developer_instructions = profile.instructions;
    }
    // lib.optionalAttrs (cfg.codex.enableCustomProvider && resolvedModel != null) {
      model = resolvedModel.model;
      model_provider = "custom-${resolvedModel.provider}";
    }
  ) allProfiles;

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
      context = builtins.readFile config.my.home.ai.harness.agentsMd.source;
      inherit settings;
    };

    home.packages = [ codex-acp-wrapped ];

    programs = {
      bash.shellAliases = shellAliases;
      fish.shellAbbrs = shellAliases;
    };

    xdg.configFile = lib.mkMerge [
      (lib.optionalAttrs generateCodexAgents (lib.mapAttrs' (name: agentCfg: {
        name = "codex/agents/${name}.toml";
        value.source = lib.my.toToml agentCfg;
      }) codexAgentConfigs))
      {
        "codex/skills" = {
          source = config.my.home.ai.harness.skillsDir;
        };
      }
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
