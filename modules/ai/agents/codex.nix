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

  codexWrapProgramArgs =
    let
      envVars = [
        "CODEX_HOME ${config.xdg.configHome}/codex"
      ]
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
      approval_policy = "on-request";
      sandbox_mode = "read-only";

      agents = {
        max_threads = 4;
        max_depth = 1;
      } // subagentConfigFiles;

      features.plugins = true;
      plugins."nixos-reactor-harness@local-repo".enabled = true;
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
    programs.fish.interactiveShellInit = ''
      codex completion fish | source
    '';

    xdg.configFile = lib.mkMerge [
      (lib.optionalAttrs generateCodexAgents (lib.mapAttrs' (name: agentCfg: {
        name = "codex/agents/${name}.toml";
        value.source = lib.my.toToml agentCfg;
      }) codexAgentConfigs))
      {
        "codex/skills" = lib.optionalAttrs config.my.home.ai.harness.enable {
          source = config.lib.file.mkOutOfStoreSymlink config.my.home.ai.harness.skillsDir;
          force = true;
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

    # https://agent-plugins.org/specification#8-client-extensions
    # https://developers.openai.com/plugins/build/plugins
    # TODO: replace to programs.codex.plugins after home-manager 26.11
    home.file.".agents/plugins/marketplace.json".text = builtins.toJSON {
      name = "local-repo";
      plugins = [
        {
          name = "nixos-reactor-harness";
          source = {
            source = "local";
            path = "./nixos-reactor-harness";
          };
          policy = {
            installation = "AVAILABLE";
            authentication = "ON_INSTALL";
          };
          category = "Productivity";
        }
      ];
    };
    my.home.ai.harness.plugins."nixos-reactor-harness" = {
      "plugins.json".extensions."com.openai" = {
        hooks = ["./hooks/hooks.json" "./com.openai/hooks/hooks.json"];
      };
      "com.openai/hooks/hooks.json" = {
        hooks = {
          PreToolUse = [
            { hooks = [
              (lib.optionalAttrs config.my.home.ai.harness.enable {
                matcher = "Bash";
                type = "command";
                command = "${pkgs.bash}/bin/bash -lc 'out=$(${config.my.home.ai.harness.codingAgentTools.rtk.package}/bin/rtk hook claude); printf \"%s\" \"$out\" | ${pkgs.jq}/bin/jq -c \"if type==\\\"object\\\" and (.hookSpecificOutput? | type==\\\"object\\\") and (.hookSpecificOutput | has(\\\"updatedInput\\\")) and ((.hookSpecificOutput.permissionDecision // \\\"\\\") != \\\"allow\\\") then .hookSpecificOutput.permissionDecision = \\\"allow\\\" elif type==\\\"object\\\" and has(\\\"updatedInput\\\") and ((.permissionDecision // \\\"\\\") != \\\"allow\\\") then .permissionDecision = \\\"allow\\\" else . end\" 2>/dev/null || printf \"%s\" \"$out\"'";
              })
            ]; }
          ];
        };
      };
    };
  };
}
