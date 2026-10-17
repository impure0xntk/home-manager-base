# ctx: local coding-agent session history, shown to agents as one search route
# and one MCP backend.
#
# This module owns what `codingAgentTools` cannot express: ctx is the only entry
# in that map with mutable state, a data root, plugins and background indexing.
#
# The projection into `codingAgentTools.ctx` lives in `projection.nix`, not here,
# and that split is load bearing. `harness/mcp.nix` reads
# `codingAgentTools.<tool>.mcpServer` for every tool, so filling that entry from
# a `config` value in the same module that also helps declare the memory
# namespace put `harness.mcp` inside the loop: mcp waited on `codingAgentTools`,
# which waited on the memory options, which waited on this module's own
# contribution. `projection.nix` reads the finished set from outside.
{ config, lib, pkgs, ... }:
let
  # `CTX_DATA_ROOT` is exported for tools that read it, but ctx itself ignores
  # the environment variable and rejects `--data-root` outside its own root, so
  # neither is relied on to select it. Nothing here sets `CTX_DAEMON_ENABLED`:
  # under `indexing.mode = auto` ctx installs and repairs its own supervisor, and
  # a wrapper disabling the daemon would fight that self-repair.
  createWrappedPackage =
    package: envVars:
    pkgs.writeShellApplication {
      name = package.meta.mainProgram;
      runtimeInputs = [ package ];
      runtimeEnv = envVars;
      text = ''
        exec ${lib.getExe package} "$@"
      '';
    };

  internals = import ./history-source-internals.nix { inherit lib pkgs; };
in
{
  options.my.home.ai.harness.memory =
    with lib;
    with lib.types;
    {
      enable = mkEnableOption "Local coding-agent session history (ctx)";

      dataRoot = mkOption {
        type = path;
        default = "${config.xdg.dataHome}/ctx";
        readOnly = true;
        description = ''
          Root holding ctx's index installation, `config.toml`, the search
          generation pointer, usage data, machine identity, and both generation
          directories. Exported history lives here too, under
          `<dataRoot>/<source>-history/`.
        '';
      };

      # `default` rather than a `config` assignment, matching `harness/hooks.nix`:
      # every other `harness.memory.*` value is either declared here or defined by
      # a module that also reads this set, so assigning `package` from `config`
      # made those readers wait on the set they were building, which evaluates as
      # infinite recursion. A `default` belongs to the declaration itself.
      package = mkOption {
        type = package;
        readOnly = true;
        default = createWrappedPackage pkgs.ctx {
          CTX_DATA_ROOT = "${config.xdg.dataHome}/ctx";
          CTX_ANALYTICS_ENABLED = "false";
          CTX_UPGRADE_AUTO = "off";
        };
        defaultText = lib.literalExpression ''createWrappedPackage pkgs.ctx { CTX_DATA_ROOT = "''${config.xdg.dataHome}/ctx"; ... }'';
        description = "ctx, with the data root baked in.";
      };

      prompt = mkOption {
        type = nullOr str;
        default = builtins.readFile ./CTX.md;
        description = "Prompt fragment describing the ctx search route.";
      };

      mcp = {
        enable = mkOption {
          type = bool;
          default = true;
          description = "Register ctx as an MCP backend.";
        };

        excludeTools = mkOption {
          type = listOf str;
          default = [
            # Modify nothing: no historical session is ever rewritten.
            "archive"
            "archive_export_bundle"
            "archive_import_bundle"
            "archive_verify_bundle"
            "import_merge_history"
            "session_delete"
            "sources_config_add_jsonl"
            "sources_config_remove_jsonl"
            "sources_config_update_jsonl"
            "sources_identity_forget"
            "sources_identity_overwrite"
            # Supervision belongs to ctx's own units, never to an agent.
            "daemon_service_install"
            "daemon_service_uninstall"
            "daemon_start"
            "daemon_stop"
            "daemon_restart"
            "setup_config_init"
            "setup_daemon"
            "install"
            "uninstall"
            "update"
            # Reach the server through `ctx-server`, if it is ever wanted.
            "server_init"
            "server_stop"
            "server_run"
            "login_start"
            "login_status"
            "logout"
            # Delegated to other backends, which are already available and
            # cheaper: rtk condenses command output, zvec-grep does lexical
            # search and codegraph answers structural questions.
            "files_read"
            "files_grep"
            "code_search"
            "tree"
            "docs"
            "document_fetch"
            "prompt_optimize"
            "look_at"
            "graph_query"
            "graph_show"
            "graph_callers"
            "graph_callees"
            "graph_impact"
            "graph_path"
            "graph_stats"
            "output_compact"
            "output_restore"
          ];
          description = ''
            Backend tool names to drop. Note `mcp-compressor` accepts one
            process-wide `--exclude-tools` pair merged across every backend and
            matched literally, so two backends exposing the same tool name cannot
            be filtered apart. Duplicates with other backends are therefore
            worth avoiding.
          '';
        };
      };

      indexing.mode = lib.mkOption {
        type = lib.types.enum [ "auto" ];
        default = "auto";
        description = ''
          Only `auto` is offered. It installs nothing and leaves the data root to
          ctx's own supervisor, which then owns daemon install and repair.
          Anything here would put a second scheduler over that same root, which is
          the conflict that corrupted this index. The enum leaves another mode one
          edit away if upstream ever stops owning the daemon, but it is not
          selectable today.
        '';
      };

      historySources = lib.mkOption {
          type = lib.types.attrsOf (import ./history-source-type.nix { inherit lib pkgs; });
          default = { };
          description = ''
            Local tools whose history ctx indexes. Each entry contributes a plugin
            manifest plus the units keeping it current.
          '';
        };
    };
  config = lib.mkIf config.my.home.ai.harness.memory.enable (
    internals.projected {
      dataRoot = config.my.home.ai.harness.memory.dataRoot;
      package = config.my.home.ai.harness.memory.package;
      sources = {
        jcode = config.my.home.ai.harness.memory.historySources.jcode;
        zerostack = config.my.home.ai.harness.memory.historySources.zerostack;
      };
    }
  );
}
