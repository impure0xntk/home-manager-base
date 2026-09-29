# jcode: RAM-efficient coding agent TUI. https://github.com/1jehuang/jcode
{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;
  harness = config.my.home.ai.harness;

  chatModel = searchModelByRole "chat";

  jcodePkg = pkgs.jcode.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/jcode/ui-toggles.patch
      ../patches/jcode/model-override.patch
    ];
  });

  jcode = pkgs.writeShellApplication {
    name = "jcode";
    runtimeInputs = [ jcodePkg ];
    runtimeEnv =
      {
        JCODE_HOME = "${config.xdg.configHome}/jcode";
        JCODE_NO_TELEMETRY = 1;
        JCODE_NO_AUTO_UPDATE = 1;
      }
      // cfg.jcode.environmentVariables;
    text = ''
      exec ${lib.getExe jcodePkg} "$@"
    '';
  };

  defaultModelOf = provider:
    let
      byRole = builtins.filter (model: builtins.elem "chat" model.roles) provider.models;
    in
    if byRole != [ ] then
      (builtins.head byRole).model
    else if provider.models != [ ] then
      (lib.head provider.models).model
    else
      null;

  apiKeyEnvOf = provider:
    let
      name = provider.api-key-env;
    in
    if name != null && builtins.match "[A-Z0-9_]+" name != null then name else null;

  jcodeProviders = lib.mapAttrs' (
    name: provider:
    let
      apiKeyEnv = apiKeyEnvOf provider;
    in
    lib.nameValuePair name (
      {
        type = "openai-compatible";
        # jcode appends `/chat/completions` itself, so the version segment is
        # part of the base URL. `my.home.ai.providers.<n>.url` carries only the
        # host, the same way qwen builds its `baseUrl` from it.
        base_url = "${provider.url}/v1";
        # jcode calls a profile "not configured" whenever its credential env var
        # is unset, and a local endpoint has no credential to set. Unlike qwen,
        # jcode has a first-class unauthenticated transport, so a provider with
        # no `api-key-env` declares `auth = "none"` instead of borrowing a
        # placeholder name that jcode would then send as a bearer token.
        auth = if apiKeyEnv != null then "bearer" else "none";
        models = map (model: { id = model.model; }) provider.models;
      }
      // lib.optionalAttrs (apiKeyEnv != null) {
        api_key_env = apiKeyEnv;
      }
      // lib.optionalAttrs (defaultModelOf provider != null) {
        default_model = defaultModelOf provider;
      }
    )
  ) (lib.listToAttrs (map (provider: lib.nameValuePair provider.name provider) cfg.providers));

  jcodeMcpServers = (lib.mapAttrs (
    name: mcp: {
      inherit (mcp) command args env enabled;
      # The registry holds a single `mcp-compressor` process, a stateless
      # multiplexer, so every session can share one instance of it.
      shared = true;
      # Already in seconds here, where qwen has to convert the same registry
      # value to milliseconds.
      timeout_secs = mcp.timeout;
    }
  ) harness.mcpServers) // cfg.jcode.extraMcpServers;

  jcodePreTool = pkgs.writeShellApplication {
    name = "jcode-pre-tool";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ../harness/hooks/jcode-pre-tool.sh);
  };

  jcodePreToolTransform = pkgs.writeShellApplication {
    name = "jcode-pre-tool-transform";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    text =
      lib.removePrefix "#!/usr/bin/env bash\n"
        (builtins.readFile ../harness/hooks/jcode-pre-tool-transform.sh);
  };

  harnessHooks = lib.optionalAttrs harness.enable {
    hooks = {
      session_start = [
        "${harness.hooks.refreshIndex.package}/bin/refresh-index .codegraph ${harness.codingAgentTools.codegraph.package}/bin/codegraph sync --quiet"
        "${harness.hooks.refreshIndex.package}/bin/refresh-index .zvec-grep ${harness.codingAgentTools.zg.package}/bin/zg index"
      ];
      # Disable PreToolUse hook: too strict
      # pre_tool = [ "${lib.getExe jcodePreTool} ${lib.getExe harness.hooks.retrievalRedirect.package}" ];
      # pre_tool_timeout_ms = 5000;
      pre_tool_transform = [
        "${lib.getExe jcodePreToolTransform} ${harness.codingAgentTools.rtk.package}/bin/rtk ${lib.getExe harness.hooks.retrievalRedirect.package}"
      ];
      pre_tool_transform_timeout_ms = 2000;
    };
  };

  baseTools = [
    # "agentgrep"
    "apply_patch"
    "bash"
    "batch"
    # "bg"
    # "browser"
    # "compile_remote"
    # "conversation_search"
    "edit"
    # "gmail"
    "integration_tools"
    "invalid"
    "jcode_docs"
    # "ls"
    # "maintainer_feedback"
    "mcp"
    "memory"
    "open"
    # "panel"
    "read"
    "replace"
    # "schedule"
    # "session_search"
    # "side_panel"
    # "skill_manage"
    "swarm"
    "todo"
    # "webfetch"
    # "websearch"
    "write"
  ];

  # `disable_base_tools` and `enabled` can only control tools
  toolsSettings = {
    disable_base_tools = cfg.jcode.baseTools.enabled == [ ];
    enabled = cfg.jcode.baseTools.enabled;
  };

  generateSwarm = cfg.subagents.enable && builtins.elem "jcode" cfg.subagents.targets;
  allSubagentProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;
  swarmWorkerProfiles = lib.filterAttrs (
    _: profile: searchModelByRole profile.model_role != null
  ) (lib.optionalAttrs generateSwarm allSubagentProfiles);

  swarmProfile =
    swarmWorkerProfiles.worker or (if builtins.length (builtins.attrNames swarmWorkerProfiles) == 1
      then builtins.head (builtins.attrValues swarmWorkerProfiles)
      else null);

  swarmSettings =
    (lib.optionalAttrs (swarmProfile != null) {
      swarm_model = (searchModelByRole swarmProfile.model_role).model;
      swarm_effort = swarmProfile.reasoning_effort;
      swarm_spawn_mode = "inline"; # visible, that spawns with tmux does not work on tmux
    }) // cfg.jcode.swarm;

  swarmPrompt = lib.optionalAttrs generateSwarm ''
    # Sub-agent roles

    These are the worker roles available in this repo. Name one in the `label`
    of a `swarm spawn` call so the coordinator can route by role.

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
      name: profile: "## ${name}\n\n${profile.instructions}"
    ) allSubagentProfiles)}
  '';

  settings = lib.my.deepMerge
    (lib.my.deepMerge
      (lib.my.deepMerge {
        tools = toolsSettings;
        features.swarm = true;
        features.check_updates = false;
        display.auto_server_reload = false;

        memory.embeddings = false; # Use harness instead.
        # Chrome this machine's TUI does not want. jcode 0.88.0 hard-wires all
        # three; the patch adds the keys behind the upstream defaults, so this is
        # the only place that has to be revisited on a version bump.
        #   features.onboarding          - the telemetry notice plus the guided
        #                                  login walkthrough, which on a machine
        #                                  whose providers are all `auth = "none"`
        #                                  is a startup wall, not guidance.
        #   display.show_header          - everything above the transcript: the
        #                                  `jcode` / `server:` / `client:` identity
        #                                  lines with their version labels, the
        #                                  provider + model line, and the
        #                                  `/login to add provider` inventory with
        #                                  one dot per unconfigured provider.
        #   display.show_prompt_numbers  - the `1> ` turn counter on the input line.
        #   display.show_info_widget     - the model / provider / session / token
        #                                  / spend / git box docked in the right
        #                                  transcript margin. This one only sets the
        #                                  launch state: `info_widget_toggle`
        #                                  (Alt+I) still brings it back.
        # `keybinding_hints` is upstream, not from the patch: it silences the
        # "learn this keybinding" nudges and the periodic status tips, which are
        # the same class of unsolicited line.
        features.onboarding = false;
        display.show_header = false;
        display.show_prompt_numbers = false;
        display.show_info_widget = false;
        display.keybinding_hints = false;
        # `[provider]` holds the session defaults; `[providers.<name>]` holds the
        # profiles they select from.
        provider = lib.optionalAttrs (chatModel != null) {
          default_provider = chatModel.provider;
          default_model = chatModel.model;
        };
        providers = jcodeProviders;
      }
      (lib.optionalAttrs (swarmSettings != { }) { agents = swarmSettings; })
    )
    harnessHooks
  ) cfg.jcode.extraSettings;
in
{
  options.my.home.ai.jcode = {
    enable = lib.mkEnableOption "Enable jcode agent";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables set for jcode.";
    };
    baseTools = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enabled = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = baseTools;
            defaultText = lib.literalExpression ''[ "agentgrep" ... ]'';
            description = ''
              Built-in tools to expose, matched literally against the names
              jcode ships. This is an allow-list over the whole tool surface,
              MCP tools included, so an entry here that names an MCP tool keeps
              it and a missing one drops it. The default is the full inventory
              jcode 0.88.0 advertises, so declaring it pins the surface rather
              than narrowing it. Set to `[ ]` to expose MCP tools only.
            '';
            example = lib.literalExpression ''[ "read" "write" "bash" "mcp" ]'';
          };
        };
      };
      default = { };
      defaultText = lib.literalExpression ''{ enabled = [ ...allBaseTools... ]; }'';
      description = ''
        Which built-in tools the jcode agent exposes. `enabled` empty means
        base tools are hidden entirely, which is the point: it is the switch
        for "MCP-provided tools only", and the generated `[tools].enabled`
        allow-list is the way to name which of those survive.
      '';
    };
    swarm = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Swarm-wide behaviour for jcode, emitted into the `[agents]` table.

        This is only for the settings the shared `my.home.ai.subagents` schema
        has no word for. The per-role model, effort and instructions come from
        `my.home.ai.subagents.profiles`, and `swarm_model` / `swarm_effort` are
        derived from the `worker` role there; declaring a role again here would
        create a second source of truth. `sandbox_mode` has no counterpart
        because jcode's permission model is not per-agent.
      '';
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra jcode `config.toml` content, merged last. Merging is recursive
        and *concatenates* lists, so entries added to `hooks` or to
        `providers.<name>.models` are appended to the generated ones rather
        than replacing them.

        The swarm keys generated by this module are set here, so a key placed
        here wins over the generated one. `my.home.ai.jcode.swarm` is the
        typed route for the ones it covers; reach for this instead only for a
        swarm key added by a newer jcode than the option knows about.
      '';
    };
    extraMcpServers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra jcode `mcp.json` content, merged last.
      '';
    };

  };

  config = lib.mkIf cfg.jcode.enable {
    home.packages = [
      jcode
    ];

    xdg.configFile = lib.mkMerge [
      {
        "jcode/config.toml".source = lib.my.toToml settings;
        "jcode/mcp.json".source = pkgs.writeText "mcp.json" (builtins.toJSON { mcpServers = jcodeMcpServers; });
        "jcode/skills" = lib.optionalAttrs harness.enable {
          source = config.lib.file.mkOutOfStoreSymlink harness.skillsDir;
          force = true;
        };
      }
      (lib.optionalAttrs
        (harness.enable && (harness.agentsMd.source != null || harness.agentsMd.text != ""))
        {
          "jcode/prompt-overlay.md".source = harness.agentsMd.source or (pkgs.writeText "prompt-overlay.md" harness.agentsMd.text);
        })
      (lib.optionalAttrs generateSwarm {
        "jcode/swarm-prompt.md" = {
          source = pkgs.writeText "swarm-prompt.md" swarmPrompt;
          force = true;
        };
      })
    ];
  };
}
