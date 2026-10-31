# fx: tiny, open, native coding agent. https://github.com/vercel-labs/fx
#
# Packaged by llm-agents.nix, so no nix-pkgs entry is needed here.
#
# fx keeps all of its state under `$HOME/.fx` and exposes no environment
# variable to move it: `src/core/shared/profile_paths.zig` derives the
# directory from `$HOME` alone. Unlike codex (CODEX_HOME) or qwen (QWEN_HOME)
# the wrapper cannot redirect it, so every file below goes through
# `home.file` rather than `xdg.configFile`. Inside the directory the agent
# uses the names the harness already owns:
#
#   harness AGENTS.md -> ~/.fx/AGENTS.md  (instructions for every project)
#   harness skills    -> ~/.fx/skills     (personal skills)
#   harness MCP       -> ~/.fx/mcp.json   (separate file from settings.json)
#
# fx 0.0.14 registers its hook kinds internally (PreToolUse, Stop,
# PostTurnEnd, AttentionRequired in src/core/hooks/definitions.zig) and reads
# none of them from a configuration file, so the harness hooks, the RTK
# rewrite and the fence audit have no route into fx yet. Permission control
# stays with fx's own `auto` review, which is why nothing below tries to
# replace it.
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
  fxHome = "${config.home.homeDirectory}/.fx";

  chatModel = searchModelByRole "chat";
  reviewModel = searchModelByRole "review";

  # Roles that reach the model through chat completions. An embedding or
  # rerank model declared alongside them is not selectable in fx, so it gets
  # no metadata entry.
  chatRoles = [
    "chat"
    "edit"
    "apply"
    "review"
  ];
  hasChatRole = model: lib.any (role: builtins.elem role chatRoles) model.roles;

  # fx accepts a connection id matching [A-Za-z][A-Za-z0-9_-]* and reserves
  # `gateway`, `codex` and `grok` case-insensitively. `my.home.ai.providers`
  # constrains `name` to `str`, so a name is scrubbed here rather than
  # emitted into a settings.json fx refuses to parse.
  reservedIds = [
    "gateway"
    "codex"
    "grok"
  ];
  providerId =
    name:
    let
      keep = c: if builtins.match "[A-Za-z0-9_-]" c != null then c else "-";
      scrubbed = lib.concatStrings (map keep (lib.stringToCharacters name));
      started = if builtins.match "[A-Za-z].*" scrubbed != null then scrubbed else "p-${scrubbed}";
    in
    if lib.elem (lib.toLower started) reservedIds then "local-${started}" else started;

  # fx names only the variable holding the credential, never the value, so a
  # provider without `api-key-env` declares no auth at all and fx omits the
  # Authorization header instead of sending a placeholder token.
  apiKeyEnvOf =
    provider:
    let
      name = provider.api-key-env;
    in
    if name != null && builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null then name else null;

  sameProviderReview = reviewModel != null && chatModel != null && reviewModel.provider == chatModel.provider;

  # Every declared provider gets a named connection, so `fx provider <name>`
  # can move between them without editing settings. `provider`/`models` below
  # only pick the default.
  connections = lib.listToAttrs (
    map
      (
        provider:
        let
          apiKeyEnv = apiKeyEnvOf provider;
          metadata = builtins.filter hasChatRole provider.models;
        in
        lib.nameValuePair (providerId provider.name) (
          {
            protocol = "openai-chat-completions";
            # The shared provider URL carries only the origin; fx appends
            # `/chat/completions` to whatever API prefix it is given. Anything
            # but loopback has to be HTTPS: `validate_url` rejects plain HTTP
            # elsewhere, and one rejected entry drops the whole providers
            # table, so a LAN gateway needs TLS or a local proxy.
            base_url = "${lib.removeSuffix "/" provider.url}/v1";
            auth = if apiKeyEnv == null then { type = "none"; } else {
              type = "bearer";
              env = apiKeyEnv;
            };
            # fx omits tool choice unless told to send it, and a coding agent
            # without tool calls is not a coding agent.
            tool_choice_mode = "send";
            # Without a declared window fx cannot work out when to compact,
            # so it never does and a long session dies on the context limit.
            model_metadata = lib.listToAttrs (
              map (model: lib.nameValuePair model.model cfg.fx.modelMetadata) metadata
            );
          }
          // lib.optionalAttrs sameProviderReview { reviewer_model = reviewModel.model; }
        )
      )
      cfg.providers
  );

  # Shared stdio MCP registry. fx takes the command as one argv list rather
  # than a command plus args, and reads its own `mcp.json` instead of folding
  # servers into settings.json.
  mcpServers = lib.mapAttrs (
    _: mcp:
    {
      type = "stdio";
      command = [ mcp.command ] ++ mcp.args;
    }
    // lib.optionalAttrs (mcp.env != { }) { env = mcp.env; }
    // lib.optionalAttrs (!mcp.enabled) { enabled = false; }
  ) harness.mcpServers;

  settings = lib.my.deepMerge
    (
      {
        permission_mode = cfg.fx.permissionMode;
        # Titles cost one extra model request per session for a label fx can
        # derive from the transcript it already has.
        session_titles = false;
        sound_level = "off";
      }
      // lib.optionalAttrs (connections != { }) { providers = connections; }
      // lib.optionalAttrs (chatModel != null) {
        provider = providerId chatModel.provider;
        models = { ${providerId chatModel.provider} = chatModel.model; };
      }
    )
    cfg.fx.extraSettings;

  additionalPrompt = ''
    ## fx specific instructions

    - `~/.fx/mcp.json` exposes the coding-agent tool registry as MCP servers. Prefer those
      tools over shelling out to search or structure commands: they answer from an index
      that is already built, so they cost less context than reading the files yourself.
  '';

  fx = pkgs.writeShellApplication {
    name = "fx";
    runtimeInputs = [ cfg.fx.package ];
    runtimeEnv = cfg.fx.environmentVariables;
    text = ''
      # Upstream checks a release manifest on startup and every 30 minutes; a
      # Nix-installed binary has no `fx upgrade` to run, so the check is noise.
      FX_AUTO_UPGRADE="''${FX_AUTO_UPGRADE:-0}"
      export FX_AUTO_UPGRADE
      exec ${lib.getExe cfg.fx.package} "$@"
    '';
  };
in

{
  options.my.home.ai.fx = {
    enable = lib.mkEnableOption "Enable fx coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fx;
      defaultText = lib.literalExpression "pkgs.fx";
      description = "The fx package to install. Ships with llm-agents.nix.";
    };

    permissionMode = lib.mkOption {
      type = lib.types.enum [
        "ask"
        "auto"
        "full-access"
      ];
      default = "auto";
      description = ''
        How fx handles tool calls that need permission. `auto` runs routine
        work and sends anything else to a review model before running it,
        which is the mode fx itself defaults to.
      '';
    };

    modelMetadata = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        context_window = 131072;
        max_output_tokens = 32768;
      };
      description = ''
        Context budget declared for every model of every provider. fx needs a
        known `context_window` to compact before it runs out of one, and a
        known `max_output_tokens` to bound a reply; neither can be read from
        an OpenAI-compatible endpoint. Set this per provider through
        `extraSettings.providers.<name>.model_metadata` when a model differs.
      '';
    };

    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables set for fx.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional fx settings.json content, merged last.";
    };

    extraMcpServers = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional entries for fx's mcp.json `mcpServers` table.";
    };
  };

  config = lib.mkIf cfg.fx.enable {
    home.packages = [ fx ];

    assertions = [
      {
        # configured_provider.zig rejects this pair outright and the whole
        # providers table with it, leaving fx with no connection at all.
        assertion = cfg.fx.modelMetadata.max_output_tokens or 0 < cfg.fx.modelMetadata.context_window or 1;
        message = "my.home.ai.fx.modelMetadata: max_output_tokens must be smaller than context_window";
      }
    ];

    # `/settings` writes back into settings.json, so the Nix source lands next
    # to it and activation installs a writable copy, the same way codex and
    # zerostack avoid fighting a read-only store path.
    home.file = lib.mkMerge [
      {
        ".fx/settings.json.orig".source = pkgs.writeText "fx-settings.json" (builtins.toJSON settings);
      }
      (lib.optionalAttrs (harness.enable) {
        ".fx/mcp.json".source = pkgs.writeText "fx-mcp.json" (builtins.toJSON { mcpServers = mcpServers // cfg.fx.extraMcpServers; });
      })
      (lib.optionalAttrs (harness.enable) {
        ".fx/skills" = {
          source = config.lib.file.mkOutOfStoreSymlink harness.skillsDir;
          force = true;
        };
      })
      (lib.optionalAttrs (harness.enable && (harness.agentsMd.source != null || harness.agentsMd.text != "")) {
        ".fx/AGENTS.md".source =
          if harness.agentsMd.source != null then
            pkgs.writeText "fx-AGENTS.md" (builtins.readFile harness.agentsMd.source + additionalPrompt)
          else
            pkgs.writeText "fx-AGENTS.md" (harness.agentsMd.text + additionalPrompt);
      })
    ];

    home.activation.installFxSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "${fxHome}/settings.json"
      install -m 644 -D "${fxHome}/settings.json.orig" "${fxHome}/settings.json"
    '';
  };
}
