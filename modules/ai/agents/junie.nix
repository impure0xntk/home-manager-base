# Junie CLI adapter for the shared AI harness.
#
# Every path and field name below was read out of the packaged 3419.29 build
# and its bundled `bundled-agents/junie-cli-docs.md` (see ./junie.md), so the
# wiring is checkable rather than guessed:
#
# - `JUNIE_HOME` holds CLI *state* and, inside it, the one thing this module
#   must write outside the XDG config tree: `$JUNIE_HOME/AGENTS.md`, Junie's
#   global guidelines, which merge with the project's own document rather than
#   replacing it.
# - The generated `config.json` is passed through `JUNIE_CONFIG_LOCATION`, and
#   `JUNIE_CONFIG_DEFAULT_LOCATIONS false` keeps Junie from merging a second,
#   hand-written user or project config on top of it.
# - `guidelines-location` is deliberately not used. It *replaces* the project
#   guideline lookup, which would drop the repository's own `AGENTS.md`.
{
  config,
  pkgs,
  lib,
  searchModelByRole,
  ...
}:
let
  cfg = config.my.home.ai;
  harness = cfg.harness;

  junieHome = "${config.xdg.dataHome}/junie";
  configPath = "junie/config.json";
  agentsPath = "junie/agents";

  # Junie reads hooks with Claude Code's matcher-entry and hook-command dialect,
  # so the harness scripts are wired unmodified. rtk is the exception: it only
  # ever speaks the Claude envelope, so its verdict is translated into Junie's
  # own output shape rather than passed through. `translate-prompt.sh` is the one
  # script not wired at all: `UserPromptSubmit` output has no field that
  # replaces the prompt, so echoing a changed `.prompt` would parse into nothing.
  harnessHooks = lib.optionalAttrs harness.enable {
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
    PreToolUse = [
      # Junie matches `PreToolUse` against the tool name the model sees, and
      # the shell tool is the only one whose payload carries a command a script
      # can judge. rtk runs before fence, never after: rtk rewrites `git commit`
      # to `rtk git commit` and fence matches rules on a literal command prefix,
      # so a hook ordered the other way round would ask fence about a command
      # the agent never runs.
      {
        matcher = "Bash";
        hooks =
          [
            {
              type = "command";
              # rtk reads the Claude envelope on stdin and answers with
              # `updatedInput`. Its verdict is translated into Junie's own
              # `PreToolUse` output shape, which is top-level `decision` plus
              # `updatedInput`; Junie has no `hookSpecificOutput` field here, so
              # emitting the Claude envelope unchanged would leave the rewrite
              # unread. The verdict is forced to `allow` so the rewrite can never
              # turn into a permission prompt: asking the user to approve a
              # command rtk itself generated is pure friction.
              command = ''
                ${pkgs.bash}/bin/bash -c '
                  out=$(${harness.codingAgentTools.rtk.package}/bin/rtk hook claude) || exit 0
                  replacement=$(printf "%s" "$out" | ${pkgs.jq}/bin/jq -r ".hookSpecificOutput.updatedInput.command // empty" 2>/dev/null) || exit 0
                  [ -n "$replacement" ] || exit 0
                  printf "%s" "$out" | ${pkgs.jq}/bin/jq -c --arg cmd "$replacement" \
                    "{decision: \"allow\", reason: \"rtk condenses this command\", updatedInput: {command: \$cmd}}"
                '
              '';
              timeout = 5;
            }
          ]
          ++ lib.optionals harness.sandbox.enable [
            {
              type = "command";
              command = lib.getExe harness.hooks.fenceAudit.package;
              timeout = 10;
            }
          ]
          ++ [
            {
              type = "command";
              command = lib.getExe harness.hooks.retrievalRedirect.package;
              timeout = 5;
            }
          ];
      }
    ];
  };

  # stdio MCP servers shared through the harness tool registry. Junie's
  # `mcp.json` schema is `mcpServers.<name>` with `command`/`args`/`env` and
  # no per-server timeout field, so the registry's `timeout` is dropped rather
  # than written as a key Junie would ignore.
  # https://junie.jetbrains.com/docs/junie-cli-mcp.html
  defaultMcpServers = lib.mapAttrs (
    name: mcp:
    {
      command = mcp.command;
      args = mcp.args;
      enabled = mcp.enabled;
    }
    // lib.optionalAttrs (mcp.env != { }) { inherit (mcp) env; }
  ) harness.mcpServers;

  # One place the wrapper's environment is assembled, so a key can be added
  # here and asserted on rather than buried in the wrapper script.
  wrapperEnv = {
    JUNIE_HOME = junieHome;
    JUNIE_SHARE_ANONYMOUS_STATISTICS = "false";
    # The generated `config.json` has to be passed explicitly: Junie skips
    # project-local hooks for safety, so hooks declared in a project's own
    # `.junie/config.json` would never run.
    JUNIE_CONFIG_LOCATION = "${config.xdg.configFile.${configPath}.source}";
    # With the default locations off, a hand-written `~/.junie/config.json`
    # cannot merge a second `hooks` object over this one.
    JUNIE_CONFIG_DEFAULT_LOCATIONS = "false";
  }
  // lib.mapAttrs (key: value: toString value) cfg.junie.environmentVariables;

  junie = pkgs.symlinkJoin {
    name = "junie";
    version = pkgs.junie.version;
    paths = [ pkgs.junie ];
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postBuild =
      let
        cfgProxy = config.my.home.networks.proxy;
        # The trailing continuation is emitted per flag rather than written
        # once at the end of the line: with the proxy off, `${proxyOpts}` is
        # empty and a fixed `\` would leave the shell reading past the
        # newline and treat the next flag as a command.
        proxyArgs =
          if cfgProxy.enable
          then "--set JAVA_TOOL_OPTIONS ${lib.escapeShellArg cfgProxy.snippet.javaOpts}"
          else "";
        # `wrapProgram` takes one command line, so each flag needs the trailing
        # continuation; a plain newline would end the command and leave the
        # next flag to the shell.
        envArgs = lib.concatStringsSep " \\\n  " (
          lib.filter (arg: arg != "") [
            proxyArgs
          ]
          ++ lib.mapAttrsToList (key: value: "--set ${key} ${lib.escapeShellArg value}") wrapperEnv
        );
      in
      ''
        wrapProgram $out/bin/junie ${envArgs}
      '';
  };

  # ── Merge built-in + extra abstract sub-agent profiles ───────────────
  allProfiles = cfg.subagents.profiles // cfg.subagents.extraProfiles;

  # ── sandbox_mode → Junie tool groups ─────────────────────────────────
  sandboxToTools = sandbox:
    if sandbox == "read-only" then [
      "Read"
      "Glob"
      "Grep"
    ]
    else if sandbox == "workspace-write" then [
      "Read"
      "Glob"
      "Grep"
      "Write"
      "Edit"
    ]
    # danger-full-access: omit the tools field -> every tool group
    else null;

  sandboxToPermissionMode = sandbox:
    if sandbox == "read-only" then
      "plan"
    else if sandbox == "workspace-write" then
      "acceptEdits"
    else
      "bypassPermissions";

  escapeYamlString = value: lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] value;

  # ── Generate Junie sub-agent .md files ───────────────────────────────
  # Format: junie/agents/<name>.md (YAML frontmatter + Markdown body).
  # https://junie.jetbrains.com/docs/junie-cli-subagents.html
  junieAgentConfigs = lib.mapAttrs' (
    name: profile:
    let
      resolvedModel = searchModelByRole profile.model_role;
      tools = sandboxToTools profile.sandbox_mode;
      toolsLine = if tools != null then "tools: [${lib.concatMapStringsSep ", " (tool: "\"${tool}\"") tools}]" else "";
      modelLine = lib.optionalString (resolvedModel != null) (
        "model: \"${escapeYamlString resolvedModel.model}\""
      );
    in
    lib.nameValuePair "${agentsPath}/${name}.md" {
      text = ''
        ---
        name: "${escapeYamlString name}"
        description: "${escapeYamlString profile.description}"
        ${toolsLine}
        ${modelLine}
        permissionMode: "${sandboxToPermissionMode profile.sandbox_mode}"
        reasoningLevel: "${profile.reasoning_effort}"
        ---

        ${profile.instructions}
      '';
    }
  ) allProfiles;

  generateJunieAgents = cfg.subagents.enable && builtins.elem "junie" cfg.subagents.targets;

  settings = {
    brave = true;
    auto-update = false;
  }
  // lib.optionalAttrs generateJunieAgents {
    # Equivalent to the default `~/.junie/agents/`, but keeps the profiles with
    # the rest of the generated configuration instead of splitting them
    # between an XDG tree and the Junie state directory.
    "agent-locations" = [ "${config.xdg.configHome}/${agentsPath}" ];
  }
  // lib.optionalAttrs (harness.enable && harness.prompts != { }) {
    # Junie reads a custom slash command from a Markdown file whose frontmatter
    # carries `description`, which is exactly the harness prompt schema.
    "command-locations" = [ harness.promptsDir ];
  }
  // lib.optionalAttrs harness.enable { hooks = harnessHooks; }
  // cfg.junie.extraSettings;
in
{
  options.my.home.ai.junie = {
    enable = lib.mkEnableOption "Enable Junie agent";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = junie;
      defaultText = lib.literalExpression "pkgs.junie wrapped with JUNIE_HOME and JUNIE_CONFIG_LOCATION";
      description = ''
        The `junie` wrapper. Exposed read-only so the environment it bakes in
        is inspectable rather than only visible inside the built script.
      '';
    };
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Additional environment variables set on the `junie` wrapper, merged
        last so a value here wins over the one this module derives.
      '';
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra Junie `config.json` content, merged last.

        Note that `hooks` from a project-local `.junie/config.json` are ignored
        by Junie for safety, so personal hooks belong here or in the file
        passed through `JUNIE_CONFIG_LOCATION`, which this module generates.
      '';
    };
    extraMcpServers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra `mcp.json` entries, merged over the harness registry.

        Junie's schema has no per-server timeout, so the harness registry's
        `timeout` is not forwarded; use `env` to tune a server's own wait.
      '';
    };
  };

  config = lib.mkIf cfg.junie.enable {
    home.packages = [ junie ];

    xdg.configFile = lib.mkMerge [
      {
        ${configPath}.text = builtins.toJSON settings;
        # Junie's documented user-scope file is `$JUNIE_HOME/mcp/mcp.json`, and
        # `$JUNIE_HOME` is the XDG data home, which home-manager does not
        # manage. The generated file is therefore installed there by activation
        # below; no `mcp-locations` entry is needed, and adding one would scan
        # the same servers a second time.
        "junie/mcp/mcp.json".text = builtins.toJSON {
          mcpServers = defaultMcpServers // cfg.junie.extraMcpServers;
        };
      }
      (lib.optionalAttrs generateJunieAgents junieAgentConfigs)
    ];

    # `$JUNIE_HOME` is the XDG data home, which home-manager does not manage,
    # so the two files Junie reads from it are installed by activation.
    home.activation = lib.mkMerge [
      (lib.optionalAttrs (harness.enable && (harness.agentsMd.source != null || harness.agentsMd.text != "")) {
        installJunieGlobalGuidelines = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p ${junieHome}
          install -m 644 ${harness.agentsMd.source or (pkgs.writeText "AGENTS.md" harness.agentsMd.text)} ${junieHome}/AGENTS.md
        '';
      })
      (lib.optionalAttrs harness.enable {
        installJunieMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p ${junieHome}/mcp
          install -m 644 ${config.xdg.configFile."junie/mcp/mcp.json".source} ${junieHome}/mcp/mcp.json
        '';
      })
    ];
  };
}
