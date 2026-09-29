# Qwen Code CLI (https://github.com/QwenLM/qwen-code).
#
# Packaged by llm-agents.nix, so no nix-pkgs entry is needed here.
#
# qwen-code keeps its whole configuration under $QWEN_HOME (default
# ~/.qwen) and never looks at XDG_CONFIG_HOME, so the package is wrapped the
# same way codex is wrapped for CODEX_HOME. Inside that directory the agent
# uses its own names for everything the harness already owns:
#
#   harness AGENTS.md -> $QWEN_HOME/AGENTS.md  (global context file)
#   harness skills    -> $QWEN_HOME/skills    (personal skills)
#   harness MCP       -> settings.json `mcpServers`
#   harness hooks     -> settings.json `hooks`
#
# Agent Plugins v1 is loaded natively (skills and MCP only): its
# `hooks/`, `agents/` and `commands/` directories are ignored, so the harness
# hooks are declared in settings.json rather than in a plugin.
# https://qwenlm.github.io/qwen-code-docs/users/extension/agent-plugins/

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

  qwenHome = "${config.xdg.configHome}/qwen";

  # qwen refuses a request whose selected route declares no readable key, even
  # against a local proxy that ignores one. Providers without `api-key-env`
  # therefore point at a dedicated name the wrapper always satisfies, so a real
  # OPENAI_API_KEY in the environment is never shadowed by a placeholder.
  placeholderApiKeyEnv = "QWEN_PLACEHOLDER_API_KEY";

  # qwen-code ships no `meta.mainProgram`, so the binary is referenced by
  # path rather than through lib.getExe.
  qwen-code-wrapped = pkgs.writeShellApplication {
    name = "qwen";
    runtimeInputs = [ pkgs.qwen-code ];
    runtimeEnv = {
      QWEN_HOME = qwenHome;
      ${placeholderApiKeyEnv} = "placeholder";
    } // cfg."qwen-code".environmentVariables;
    text = ''
      exec ${pkgs.qwen-code}/bin/qwen "$@"
    '';
  };

  chatModel = searchModelByRole "chat";

  # `openai` is a built-in provider id and already routes the
  # OpenAI-compatible Chat Completions wire, so every configured provider is
  # declared under it with its own baseUrl/envKey. A custom id would need a
  # `providerProtocol` entry, while `security.auth.selectedType` only accepts
  # a built-in protocol, so the indirection buys nothing here. A model is
  # identified by (protocol, id, baseUrl), so two providers may reuse an id
  # at different baseUrls.
  qwenModels = lib.concatMap
    (provider: map (model: {
      id = model.model;
      wireApi = "chat-completions";
      baseUrl = "${provider.url}/v1";
      # `api-key-env` defaults to null rather than being absent, so `or` would
      # not fall back to the placeholder here.
      envKey = if provider.api-key-env != null then provider.api-key-env else placeholderApiKeyEnv;
    }) provider.models)
    cfg.providers;

  # stdio MCP servers shared through harness tool registry.
  # qwen reads them from `mcpServers` in ~/.qwen/settings.json, and its
  # `timeout` is milliseconds where the registry keeps seconds.
  # https://qwenlm.github.io/qwen-code-docs/users/features/mcp/
  defaultMcpServers = lib.mapAttrs
    (name: mcp: {
      command = mcp.command;
      args = mcp.args;
      timeout = mcp.timeout * 1000;
    } // lib.optionalAttrs (mcp.env != { }) {
      inherit (mcp) env;
    })
    harness.mcpServers;

  # qwen speaks the Claude hook dialect in settings.json, so the same three
  # events codex and goose wire up are wired up here, with qwen's tool names.
  # https://qwenlm.github.io/qwen-code-docs/users/features/hooks/
  harnessHooks = {
    SessionStart = [
      {
        hooks = [
          {
            type = "command";
            command = "${harness.hooks.refreshIndex.package}/bin/refresh-index .codegraph ${harness.codingAgentTools.codegraph.package}/bin/codegraph sync --quiet";
            timeout = 30;
          }
          {
            type = "command";
            command = "${harness.hooks.refreshIndex.package}/bin/refresh-index .zvec-grep ${harness.codingAgentTools.zg.package}/bin/zg index";
            timeout = 300;
          }
        ];
      }
    ];
    UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = "${harness.hooks.translatePrompt.package}/bin/translate-prompt ${harness.codingAgentTools.codegraph.package}/bin/codegraph prompt-hook";
            timeout = 30;
          }
        ];
      }
    ];
    PreToolUse = [
      # codegraph and zvec-grep are registered as MCP servers above, so raw
      # read/search/structure calls spend context on a weaker answer than the
      # index gives back. The names are qwen's own; the script judges the
      # leading command fragment, not the tool.
      # {
      #   matcher = "^(run_shell_command|list_directory|glob|read_file|grep_search)$";
      #   hooks = [
      #     {
      #       type = "command";
      #       command = lib.getExe harness.hooks.retrievalRedirect.package;
      #       timeout = 5;
      #     }
      #   ];
      # }
      {
        # Shell tool is the only surface `rtk` can rewrite into the command.
        matcher = "^run_shell_command$";
        hooks = [
          {
            type = "command";
            command = "${pkgs.bash}/bin/bash -lc 'in=$(cat); if cmd=$(printf \"%s\" \"$in\" | ${pkgs.jq}/bin/jq -r \".tool_input.command // empty\" 2>/dev/null) && [ -n \"$cmd\" ]; then out=$(printf \"%s\" \"$in\" | ${harness.codingAgentTools.rtk.package}/bin/rtk hook claude); printf \"%s\" \"$out\" | ${pkgs.jq}/bin/jq -c --arg orig \"$cmd\" \"if ((.hookSpecificOutput.updatedInput.command // \\\"\\\") != \\\"\\\") and ((.hookSpecificOutput.updatedInput.command // \\\"\\\") != \\$orig) then {decision: \\\"block\\\", reason: (\\\"Token savings: use \\`\\\" + .hookSpecificOutput.updatedInput.command + \"\\` instead\\\")} else empty end\" 2>/dev/null || true; fi'";
            timeout = 10;
          }
        ];
      }
    ];
  };

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  sandboxToApprovalMode =
    sandbox: if sandbox == "read-only" then "plan" else if sandbox == "workspace-write" then "auto-edit" else "yolo";

  sandboxToTools =
    sandbox:
    if sandbox == "read-only" then [
      "read_file"
      "grep_search"
      "glob"
      "list_directory"
      "web_search"
      "web_fetch"
      "lsp"
    ]
    else if sandbox == "workspace-write" then [
      "read_file"
      "grep_search"
      "glob"
      "list_directory"
      "web_search"
      "web_fetch"
      "lsp"
      "run_shell_command"
      "edit"
      "write_file"
    ]
    # danger-full-access: omit tools field -> all tools
    else null;

  escapeYamlString = value: lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] value;

  # ── Generate Qwen Code subagent .md files ───────────────────────────
  # Format: qwen/agents/<name>.md (YAML frontmatter + Markdown body)
  # https://qwenlm.github.io/qwen-code-docs/users/features/sub-agents/
  qwenAgentConfigs = lib.mapAttrs' (
    name: profile:
    let
      resolvedModel = searchModelByRole profile.model_role;
      tools = sandboxToTools profile.sandbox_mode;
      toolsLine = if tools != null then "tools: [${lib.concatMapStringsSep ", " (tool: "\"${tool}\"") tools}]" else "";
      modelLine = lib.optionalString (resolvedModel != null) "model: \"${escapeYamlString resolvedModel.model}\"";
    in
    lib.nameValuePair "qwen/agents/${name}.md" {
      text = ''
        ---
        name: "${escapeYamlString name}"
        description: "${escapeYamlString profile.description}"
        ${modelLine}
        ${toolsLine}
        approvalMode: "${sandboxToApprovalMode profile.sandbox_mode}"
        ---

        ${profile.instructions}
      '';
    }
  ) allProfiles;

  generateQwenAgents = cfg.subagents.enable && builtins.elem "qwen" cfg.subagents.targets;

  # lib.my.deepMerge takes one pair, so the layers fold left. Each later layer
  # therefore wins key by key, with nested attrsets merged rather than replaced,
  # which is what the agent option `extraSettings` relies on.
  settings = lib.foldl' lib.my.deepMerge { } [
    {
      privacy.usageStatisticsEnabled = false;
      security.auth.selectedType = "openai";
      modelProviders.openai = qwenModels;
    }
    (lib.optionalAttrs (chatModel != null) {
      model = {
        name = chatModel.model;
        # Model selection is by id, so the baseUrl is what disambiguates a model
        # id declared by more than one provider.
        baseUrl = "${chatModel.url}/v1";
      };
    })
    (lib.optionalAttrs harness.enable {
      mcpServers = defaultMcpServers;
      hooks = harnessHooks;
    })
    cfg."qwen-code".extraSettings
  ];

  shellAliases = {
    qw = "qwen";
  };
in

{
  options.my.home.ai.qwen-code = {
    enable = lib.mkEnableOption "Enable Qwen Code agent";
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables set for qwen.";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Qwen Code settings.json overrides, merged last.";
    };
  };

  config = lib.mkIf cfg."qwen-code".enable {
    home.packages = [ qwen-code-wrapped ];

    xdg.configFile = lib.mkMerge [
      {
        "qwen/settings.json".text = builtins.toJSON settings;
      }
      (lib.optionalAttrs generateQwenAgents qwenAgentConfigs)
      (lib.optionalAttrs
        (harness.enable && (harness.agentsMd.source != null || harness.agentsMd.text != ""))
        {
          # Qwen reads QWEN.md and AGENTS.md from $QWEN_HOME as global context
          # files, so the harness document is installed under the name the
          # agent already looks for.
          "qwen/AGENTS.md".source = harness.agentsMd.source or (pkgs.writeText "AGENTS.md" harness.agentsMd.text);
          "qwen/skills" = {
            source = config.lib.file.mkOutOfStoreSymlink harness.skillsDir;
            force = true;
          };
        })
    ];

    programs = {
      bash.shellAliases = shellAliases;
      fish.shellAbbrs = shellAliases;
    };
  };
}
