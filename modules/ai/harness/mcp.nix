# Agent agnostic MCP server registry.
#
# `my.home.ai.harness.codingAgentTools.<tool>.mcpServer` stays the single
# source of truth. This module only projects those declarations into
# `mcpServers`, so every agent module can translate the same registry into its
# own configuration format without knowing about other agents:
#
# - codex: `[mcp_servers.<name>]` tables in ~/.codex/config.toml
# - goose: `extensions.<name>` `type: stdio` in ~/.config/goose/config.yaml
#
# Every declared backend is multiplexed behind a single `mcp-compressor`
# process through its `--multi-server` flag, so agents register one MCP server
# instead of one per tool. With more than one backend, `mcp-compressor` prefixes
# its wrapper tools with the backend name (`codegraph_invoke_tool`,
# `zg_get_tool_schema`, ...), hence the backend name is the tool name. Per tool
# env rides inside its own `--multi-server` value, never on the compressor.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  harness = config.my.home.ai.harness;
  cfg = harness.mcp;

  # Tools without an MCP surface (rtk) declare `mcpServer = null`.
  toolMcpServers = lib.filterAttrs (_: mcp: mcp != null) (
    lib.mapAttrs (_: tool: tool.mcpServer) harness.codingAgentTools
  );
  enabledMcpServers = lib.filterAttrs (_: mcp: mcp.enabled) toolMcpServers;

  # `--multi-server "name=command [args...]"`, one flag per backend. The value is
  # re-split into words by the backend argument parser, so a command, its
  # arguments and the env declarations must not contain whitespace.
  # `mcp-compressor` has no per backend env flag, so the tool env leads the
  # backend command and reaches the backend as its own arguments:
  # `<name>=<env> KEY=VALUE ... <command> [args...]`. Putting env on the backend
  # rather than on the compressor keeps two tools declaring the same key with
  # different values independent instead of a global merge conflict.
  multiServerArgs = lib.concatMap (
    name:
    let
      mcp = toolMcpServers.${name};
      envAssignments = lib.mapAttrsToList (key: value: "${key}=${value}") mcp.env;
      spec = lib.concatStringsSep " " (
        lib.flatten [
          (lib.getExe' pkgs.coreutils "env")
          envAssignments
          mcp.command
          mcp.args
        ]
      );
    in
    lib.optionals mcp.enabled [
      "--multi-server"
      "${name}=${spec}"
    ]
  ) (lib.attrNames toolMcpServers);

  # A single `invoke_tool` call pays for the compressor plus its backend, so the
  # shared entry inherits the largest declared per-tool timeout.
  # `mcp-compressor` has no per backend filter flag: `--include-tools` and
  # `--exclude-tools` are process wide, so every backend contributes to a
  # single deduplicated pair of flags. Names are matched literally, therefore
  # two backends exposing the same tool name cannot be filtered apart.
  toolFilterArgs =
    flag: optionName:
    let
      names = lib.unique (
        lib.sort builtins.lessThan (lib.concatMap (mcp: mcp.${optionName}) (lib.attrValues toolMcpServers))
      );
    in
    lib.optionals (names != [ ]) [
      flag
      (lib.concatStringsSep "," names)
    ];

  includeToolArgs = toolFilterArgs "--include-tools" "includeTools";
  excludeToolArgs = toolFilterArgs "--exclude-tools" "excludeTools";

  timeout = lib.foldl' (acc: mcp: lib.max acc mcp.timeout) 0 (lib.attrValues enabledMcpServers);
in
{
  options.my.home.ai.harness.mcp = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "compressed-tools";
      description = ''
        Name agents register the multiplexed MCP server under
        (`mcp_servers.<name>` in codex, `extensions.<name>` in goose).
      '';
    };
    # `max` only drops a name-level listing (`<tool>name</tool>`) and adds a
    # `list_tools` tool, so the agent has to spend a round trip on `list_tools`
    # before it even knows the argument names. `high` puts them in the
    # `get_tool_schema` description itself, so the first call is already an
    # `invoke_tool`. Measured per backend with the zvec-grep backend: `max` is
    # 3 frontend tools and 1031 B of `tools/list`; `high` is 2 frontend tools
    # and 1182 B, i.e. about 37 tokens more resident per backend in exchange for
    # removing the discovery round trip.
    compression = lib.mkOption {
      type = lib.types.enum [
        "low"
        "medium"
        "high"
        "max"
      ];
      default = "high";
      description = "mcp-compressor compression level used for the multiplexed server.";
    };
  };

  options.my.home.ai.harness.mcpServers = lib.mkOption {
    type = lib.types.attrsOf (import ./mcp-server-type.nix { inherit lib; });
    readOnly = true;
    default = lib.optionalAttrs (enabledMcpServers != { }) {
      ${cfg.name} = {
        command = lib.getExe pkgs.my.mcp-compressor;
        args = [
          "--compression"
          cfg.compression
          "--toonify"
        ]
        ++ multiServerArgs
        ++ includeToolArgs
        ++ excludeToolArgs;
        inherit timeout;
      };
    };
    description = ''
      MCP servers declared in `codingAgentTools`, multiplexed into the single
      `mcp-compressor` server named by `harness.mcp.name`. Tools without
      `mcpServer` and tools with `enabled = false` are omitted. The
      `mcpServer.includeTools` and `mcpServer.excludeTools` of every backend
      are merged into the single process wide `--include-tools` and
      `--exclude-tools` pair that `mcp-compressor` accepts.
    '';
  };
}
