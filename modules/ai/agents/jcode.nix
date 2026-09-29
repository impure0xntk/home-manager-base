# jcode: RAM-efficient coding agent TUI. https://github.com/1jehuang/jcode
#
# jcode differs from codex, goose and qwen-code in six ways that shape this
# file, so none of their configuration shapes carry over:
#
# 1. It keeps its state in a directory of its own, `$HOME/.jcode`, not in
#    `$XDG_CONFIG_HOME`, so the only lever for relocating it is `JCODE_HOME`.
#    That is the same redirect `CODEX_HOME` and `QWEN_HOME` perform, and it puts
#    everything under `xdg.configFile` like every other agent module here.
#    The price is that jcode reads a non-default `JCODE_HOME` as a *sandboxed*
#    home and moves its `$HOME`-relative lookups (`AGENTS.md`, `.agents/skills`,
#    `.claude/mcp.json`, `.codex/*`, every other agent's credential store) under
#    `$JCODE_HOME/external/`. The harness document therefore goes to
#    `prompt-overlay.md` and the harness skills to `$JCODE_HOME/skills`, both of
#    which resolve through jcode's own directory and stay unsandboxed.
#
# 2. Its config is one TOML file with a different table layout, not the
#    per-agent manifest each of the other three writes. Provider selection goes
#    through named `[providers.<name>]` profiles plus a `[provider]` table of
#    defaults, and MCP servers live in a *separate* JSON file with a
#    Claude-Code-shaped `mcpServers` key.
#
# 3. Its hooks are not the Claude hook dialect codex, goose and qwen all speak.
#    Each event is one command string under `[hooks]`, a gate reports through an
#    exit code instead of JSON on stdout, and the shell rewrite is a
#    `pre_tool_transform` whose stdin and stdout are the tool input itself. One
#    adapter per harness script bridges that, so the shared scripts stay shared.
#
# 4. The TUI chrome is trimmed by four keys that upstream 0.88.0 does not have.
#    `patches/jcode/ui-toggles.patch` adds them behind the upstream defaults,
#    applied to `pkgs.jcode` with `overrideAttrs`, and the `settings` below sets
#    each to false. See the comments there.
#
# 5. `--model` reaches only a server this process spawns, so against the
#    persistent daemon it is dropped with a warning. `patches/jcode/
#    model-override.patch` hands it from the client to the attached session
#    over the same `Request::SetModel` the in-TUI `/model` command sends, which
#    also means a route prefix (`openai-api:gpt-5.5`) can switch the provider
#    from the command line. The client sends it whether or not it also spawned
#    the daemon, which is what makes the spawn case work: `serve` receives
#    `--model` and logs `Using model:`, but the server rebuilds its provider per
#    new session and that rebuild carries a CLI selection over only when a
#    *provider* was named explicitly, so a bare `--model` falls back to
#    `[provider].default_model`. `--provider` stays server-start only, because
#    the provider is chosen once at `serve` bootstrap and every session inherits
#    it.
#
# 6. It manages its own daemon binary under `$JCODE_HOME/builds` and prefers
#    that over the executable it was launched from once the `shared-server` and
#    `stable` channels agree. The Nix package sets `JCODE_RELEASE_BUILD`, so left
#    alone it downloads a release on first run and re-execs into it, silently
#    replacing the pinned version -- and on a NixOS machine failing outright,
#    because the published release is a glibc build with no
#    `/lib64/ld-linux-x86-64.so.2` to load it with. Both the updater and the
#    auto-reload are therefore switched off below.
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

  # Everything below is named relative to `xdg.configFile`, and the wrapper
  # points `JCODE_HOME` at the same directory, so `$XDG_CONFIG_HOME/jcode` is
  # where jcode looks for all of it.
  chatModel = searchModelByRole "chat";

  # jcode ships no configuration key for some pieces of chrome this machine
  # does not want, so the keys are added by patch rather than configuration. The
  # package itself stays `pkgs.jcode`: only the patches are added, which leaves
  # llm-agents owning the version, the source hash, and the cargo hash, and
  # leaves every other consumer of the attribute on this machine unpatched.
  # `patches` is a `mkDerivation` attribute consumed during `patchPhase`, so the
  # vendor closure -- and therefore `cargoHash` -- is unaffected.
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
        # `JCODE_HOME` is the only way to move jcode off `$HOME/.jcode`, and
        # it has to name the same directory `xdg.configFile` writes into or
        # jcode reads a config that was never written.
        JCODE_HOME = "${config.xdg.configHome}/jcode";
        JCODE_NO_TELEMETRY = 1;
        # jcode self-manages a daemon binary under `$JCODE_HOME/builds` and
        # prefers that over the executable it was launched from whenever the
        # `shared-server` and `stable` channels agree. The Nix package sets
        # `JCODE_RELEASE_BUILD`, so without this it downloads a release on
        # first run and then re-execs into it -- silently replacing the
        # pinned package version, and on a NixOS machine failing outright,
        # because the published release is a glibc build and there is no
        # `/lib64/ld-linux-x86-64.so.2` to load it with. Suppressing the
        # updater keeps `pkgs.jcode` authoritative.
        JCODE_NO_AUTO_UPDATE = 1;
      }
      // cfg.jcode.environmentVariables;
    text = ''
      exec ${lib.getExe jcodePkg} "$@"
    '';
  };

  # The model a profile opens with: the first model declaring the `chat` role,
  # or the profile's first model when none does. jcode keys a model by
  # (profile, id) rather than by id alone, so two providers exposing the same
  # model id coexist here without the `custom-<provider>` prefixing codex needs.
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

  # jcode aborts a profile whose credential variable name it cannot read: its
  # `is_safe_env_key_name` accepts `[A-Z0-9_]+` and nothing else, and an
  # invalid `api_key_env` fails the whole server at startup rather than
  # degrading. A placeholder that exists only to satisfy another agent -- qwen's
  # `dummy`, for instance -- is not such a name, and it also points at no
  # credential, so it renders exactly like a provider that declares no
  # `api-key-env` at all: jcode's own unauthenticated transport.
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

  # jcode keeps MCP servers out of `config.toml` and in `$JCODE_HOME/mcp.json`,
  # under the Claude-Code `mcpServers` key. It speaks stdio only, which is all
  # the harness registry holds, so every entry translates directly. It also
  # imports `~/.codex/config.toml` into this file on first run -- but only while
  # the file is missing, so managing it here also keeps Codex's servers from
  # being copied in behind the registry. (`~/.codex` is a `$HOME`-relative path
  # the redirect above sandboxes anyway, so the managed file is the only source
  # either way.)
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
      # jcode's SessionStart. An observer, so it is spawned detached and
      # fire-and-forget, which is the right shape for an index refresh. It runs
      # in the session's own working directory, which is the directory the marker
      # check inside refresh-index resolves from.
      session_start = [
        "${harness.hooks.refreshIndex.package}/bin/refresh-index .codegraph ${harness.codingAgentTools.codegraph.package}/bin/codegraph sync --quiet"
        "${harness.hooks.refreshIndex.package}/bin/refresh-index .zvec-grep ${harness.codingAgentTools.zg.package}/bin/zg index"
      ];
      # The gate. jcode blocks a tool call on exit 2 and hands the hook's stderr
      # back to the model as the tool error, so this is the only channel the
      # deny message can arrive through.
      pre_tool = [ "${lib.getExe jcodePreTool} ${lib.getExe harness.hooks.retrievalRedirect.package}" ];
      pre_tool_timeout_ms = 5000;
      # The rtk rewrite the other agents run as a second PreToolUse hook, but
      # expressed the way jcode wants it: the transformer replaces the tool
      # input before it is validated rather than rejecting the call.
      #
      # The same gate is handed over as the second argument because jcode runs
      # transformers *before* the pre_tool gate. Without it every command rtk
      # rewrites reaches the gate already rewritten, so the read shapes the gate
      # exists to deny -- `cat foo.nix` becomes `rtk read foo.nix` -- would be
      # judged in the one form the gate does not recognise and pass. Consulting
      # the gate here drops the rewrite instead, which leaves the original
      # command to reach the gate on its own and be denied with a message that
      # names the index tools.
      pre_tool_transform = [
        "${lib.getExe jcodePreToolTransform} ${harness.codingAgentTools.rtk.package}/bin/rtk ${lib.getExe harness.hooks.retrievalRedirect.package}"
      ];
      # jcode's own default is 500 ms, which is one process spawn; the rewrite
      # spawns rtk and jq and now also the gate, so it needs more headroom than
      # a pure filter.
      pre_tool_transform_timeout_ms = 2000;
    };
  };

  # jcode ships these names, and `[tools].enabled` is matched literally against
  # them, so the list doubles as the base tool inventory this module knows about.
  # Measured against jcode 0.88.0: it sends exactly these 30 plus whatever the
  # MCP registry contributes, so anything jcode adds upstream shows up as a
  # missing entry here rather than as a silent no-op.
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

  # `[tools]` in `config.toml`. Both keys are load-bearing together:
  # `disable_base_tools` hides every built-in, MCP included, and `enabled` opts
  # tools back in by exact name. Neither alone does what it looks like it does,
  # so the option is expressed as a single pair rather than two flags a caller
  # has to remember to combine.
  #
  # `enabled` filters MCP tools too: with `enabled = ["read"]` the advertised
  # schema was exactly `read`, MCP excluded. So this list selects the whole
  # surface, not just the base half of it.
  # An empty allow-list is what "MCP only" looks like, so it is what flips the
  # base tool switch. Comparing against `[ ]` rather than negating the list:
  # `!` on a list leans on Nix truthiness, where any non-empty list is true and
  # `[]` is false. That happens to give the right answer, but only by accident
  # of coercion, and a reader cannot tell that from the expression.
  toolsSettings = {
    disable_base_tools = cfg.jcode.baseTools.enabled == [ ];
    enabled = cfg.jcode.baseTools.enabled;
  };

  # jcode has no per-subagent profile format, so the shared
  # `my.home.ai.subagents` schema cannot reach it the way it reaches codex
  # (`agents/<name>.toml`) or goose (`recipes/<name>.yaml`). What jcode reads is
  # one flat `[agents]` table of swarm defaults and one prompt file every worker
  # shares, so the profile shape lives here, under jcode, rather than widening a
  # global option with fields only one adapter can honour.
  #
  # Two shared-schema fields have no counterpart and are dropped rather carried
  # as dead weight: `description` folds into the prompt file, and `sandbox_mode`
  # is absent because jcode's permission model is not per-agent. Effort uses
  # jcode's own vocabulary rather the shared low/medium/high, so a value here is
  # never silently reinterpreted against a different enum.
  jcodeEffortLevels = [ "none" "minimal" "low" "medium" "high" "xhigh" "max" ];
  swarmProfileType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Short description of the role, shown in the swarm prompt file.";
      };
      instructions = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Persistent instructions passed to this swarm worker role.";
      };
      model_role = lib.mkOption {
        type = lib.types.enum [ "chat" "edit" "apply" "autocomplete" ];
        default = "chat";
        description = "Logical model role resolved against configured providers.";
      };
      reasoning_effort = lib.mkOption {
        type = lib.types.enum jcodeEffortLevels;
        default = "medium";
        description = "Reasoning effort requested from this swarm worker role.";
      };
    };
  };

  # A profile whose role no provider declares cannot produce a model string.
  # Dropping it keeps the emitted table valid; emitting null would serialize as
  # a bare `swarm_model = ` line jcode cannot parse back.
  swarmWorkerProfiles = lib.filterAttrs (
    _: profile: searchModelByRole profile.model_role != null
  ) (lib.optionalAttrs cfg.jcode.swarm.enable cfg.jcode.swarm.subagents);

  # One profile wins the single `swarm_model` / `swarm_effort` slot, so the pick
  # is explicit rather first-wins. `worker` is the natural default: it is the
  # role whose job is doing scoped work, and the only one a single model
  # setting can honestly describe.
  swarmProfile =
    swarmWorkerProfiles.worker or (if builtins.length (builtins.attrNames swarmWorkerProfiles) == 1
      then builtins.head (builtins.attrValues swarmWorkerProfiles)
      else null);

  # `[agents]` is emitted as a merge layer of its own rather than as a key of
  # the settings set, because an empty `agents` still serializes as a bare
  # `[agents]` header. A layer that disappears when swarm is off keeps the table
  # out of the file entirely rather than handing jcode an empty one.
  swarmSettings = lib.optionalAttrs cfg.jcode.swarm.enable (
    lib.optionalAttrs (swarmProfile != null) {
      # jcode wants a bare model id, not the `provider/model` pair the
      # coordinator resolves, because the worker session picks its own provider
      # from `providers.<name>.models`.
      swarm_model = (searchModelByRole swarmProfile.model_role).model;
      swarm_effort = swarmProfile.reasoning_effort;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.rootEffort != null) {
      swarm_root_effort = cfg.jcode.swarm.rootEffort;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.deepRootEffort != null) {
      swarm_deep_root_effort = cfg.jcode.swarm.deepRootEffort;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.maxConcurrentAgents != null) {
      swarm_max_concurrent_agents = cfg.jcode.swarm.maxConcurrentAgents;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.spawnMode != null) {
      swarm_spawn_mode = cfg.jcode.swarm.spawnMode;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.stripLayout != null) {
      swarm_strip_layout = cfg.jcode.swarm.stripLayout;
    }
    // lib.optionalAttrs (cfg.jcode.swarm.galleryMaxPct != null) {
      swarm_gallery_max_pct = cfg.jcode.swarm.galleryMaxPct;
    }
  );

  # jcode reads the swarm worker prompt from `$JCODE_HOME/swarm-prompt.md`, a
  # single file rather a per-agent directory, so every role's instructions
  # collapse into one document. Each keeps its name as a heading so a
  # coordinator can still route by role when it labels a `swarm spawn` call.
  swarmPrompt = lib.optionalAttrs cfg.jcode.swarm.enable ''
    # Sub-agent roles

    These are the worker roles available in this repo. Name one in the `label`
    of a `swarm spawn` call so the coordinator can route by role.

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
      name: profile: "## ${name}\n\n${profile.instructions}"
    ) swarmWorkerProfiles)}
  '';

  # `deepMerge` concatenates lists rather than replacing them, so a hook or a
  # model list in `extraSettings` is appended to the generated one instead of
  # overriding it. That is the same trade the other agent modules make.
  #
  # `agents` is merged as a layer of its own rather than as a key of the set
  # below, because an empty `agents` still serializes as a bare `[agents]`
  # header. Keeping it in a layer that disappears when swarm is off leaves the
  # table out of the file entirely rather than giving jcode an empty one.
  settings = lib.my.deepMerge
    (lib.my.deepMerge
      (lib.my.deepMerge {
        tools = toolsSettings;
        # The package is the version manager here, so jcode neither asks GitHub for
        # a newer release nor acts on one. Both would write into `$JCODE_HOME/builds`
        # and re-exec into a binary Nix does not know about.
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
    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra jcode `config.toml` content, merged last. Merging is recursive
        and *concatenates* lists, so entries added to `hooks` or to
        `providers.<name>.models` are appended to the generated ones rather
        than replacing them.
      '';
    };
    swarm = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Emit jcode `[agents]` swarm settings and a swarm prompt";
          subagents = lib.mkOption {
            type = lib.types.attrsOf swarmProfileType;
            default = { };
            description = ''
              Swarm worker roles, keyed by the name a coordinator passes as the
              `label` of a `swarm spawn` call. Each role's `instructions`
              becomes a section of `jcode/swarm-prompt.md`, which every worker
              reads, so this is role guidance and not a guarantee that a
              particular worker ran under it.
            '';
            example = lib.literalExpression ''
              {
                reviewer = {
                  description = "Read-only diff review";
                  instructions = "Review the diff and report findings. Do not edit files.";
                  model_role = "chat";
                  reasoning_effort = "high";
                };
              }
            '';
          };
          rootEffort = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum jcodeEffortLevels);
            default = null;
            description = ''
              Effort for a root coordinator. Left unset jcode applies its own
              default, so this stays null unless a value is wanted
              deliberately.
            '';
          };
          deepRootEffort = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum jcodeEffortLevels);
            default = null;
            description = "Effort for a coordinator running in `swarm-deep` mode.";
          };
          maxConcurrentAgents = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Upper bound on live swarm workers.";
          };
          spawnMode = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "visible" "headless" "inline" "auto" ]);
            default = null;
            description = ''
              How a `swarm spawn` creates its worker. Left unset jcode uses
              `inline`, which keeps a spawned worker off the desktop's TUI.
            '';
          };
          stripLayout = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "vertical" "horizontal" ]);
            default = null;
            description = "Layout of the inline swarm strip above the status line.";
          };
          galleryMaxPct = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 0 100);
            default = null;
            description = "Height of the inline gallery viewport as a percentage of the terminal.";
          };
        };
      };
      default = { };
      description = ''
        jcode `[agents]` swarm configuration, rendered into
        `jcode/config.toml` plus a `jcode/swarm-prompt.md` worker prompt.

        The profile shape is defined here rather than added to
        `my.home.ai.subagents` because jcode has no per-agent profile format.
        Codex and Goose translate the shared schema into a file per agent;
        jcode reads a single flat `[agents]` table and a single prompt file, so
        a shared field with no counterpart there (`sandbox_mode`) would exist
        only to be ignored.

        `swarm_model` and `swarm_effort` are a single pair, not one per role.
        The role named `worker` supplies them, or the only role if exactly one
        is configured; with several roles and no `worker`, the two keys are
        omitted and every worker falls back to the coordinator's own model.
        Individual roles can still be routed at `swarm spawn` time with an
        explicit `model` and `effort`, which takes priority over these keys.
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
        # `source` rather than `text`: the generated TOML names the harness tool
        # store paths, and a `text` value is a string that may not carry a store
        # path. `lib.my.toToml` returns a derivation, so `text` would have to read
        # it back with a context attached, which is exactly what that check
        # rejects.
        "jcode/config.toml".source = lib.my.toToml settings;
        "jcode/mcp.json".source = pkgs.writeText "mcp.json" (builtins.toJSON { mcpServers = jcodeMcpServers; });
        # jcode's own global skills directory, resolved through `JCODE_HOME` and
        # therefore not sandboxed. It has to be populated here because the shared
        # `~/.agents/skills` is one of the `$HOME`-relative lookups `JCODE_HOME`
        # moves under `external/`, and its presence also stops jcode from doing a
        # one-time import of Claude Code and Codex skills into a directory we
        # manage.
        "jcode/skills" = lib.optionalAttrs harness.enable {
          source = config.lib.file.mkOutOfStoreSymlink harness.skillsDir;
          force = true;
        };
      }
      (lib.optionalAttrs
        (harness.enable && (harness.agentsMd.source != null || harness.agentsMd.text != ""))
        {
          # jcode assembles its system prompt from a base prompt, `./AGENTS.md`
          # and `~/AGENTS.md`, then an overlay from `./.jcode/` and
          # `$JCODE_HOME/`. The harness document belongs in the global overlay: it
          # is guidance appended to every session, and claiming `~/AGENTS.md` for
          # a file every other agent on the machine also reads would make the
          # harness document a cross-tool side effect. The overlay also resolves
          # through `JCODE_HOME`, so the redirect above cannot hide it.
          "jcode/prompt-overlay.md".source = harness.agentsMd.source or (pkgs.writeText "prompt-overlay.md" harness.agentsMd.text);
        })

      # jcode reads worker guidance from `$JCODE_HOME/swarm-prompt.md` and falls
      # back to `./.jcode/swarm-prompt.md` for a repo. Both live inside the
      # config home here, so the roles stay next to the rest of the jcode
      # configuration instead of in an unmanaged dotfile in the working tree.
      # `force` is needed because a stray `~/.config/jcode/swarm-prompt.md`
      # would otherwise fail the activation.
      (lib.optionalAttrs cfg.jcode.swarm.enable {
        "jcode/swarm-prompt.md" = {
          source = pkgs.writeText "swarm-prompt.md" swarmPrompt;
          force = true;
        };
      })
    ];
  };
}
