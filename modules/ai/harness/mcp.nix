# Agent agnostic MCP server registry.
#
# `my.home.ai.harness.codingAgentTools.<tool>.mcpServer` stays the single
# source of truth. This module only projects those declarations into
# `mcpServers`, so every agent module can translate the same registry into its
# own configuration format without knowing about the other agents:
#
#   - codex: `[mcp_servers.<name>]` tables in ~/.codex/config.toml
#   - goose: `extensions.<name>` with `type: stdio` in ~/.config/goose/config.yaml
{
  config,
  lib,
  ...
}:

let
  harness = config.my.home.ai.harness;
in
{
  options.my.home.ai.harness.mcpServers = lib.mkOption {
    type = lib.types.attrsOf (import ./mcp-server-type.nix { inherit lib; });
    readOnly = true;
    default =
      lib.filterAttrs (_: mcp: mcp != null) (
        lib.mapAttrs (_: tool: tool.mcpServer) harness.codingAgentTools
      );
    description = ''
      MCP servers declared by `codingAgentTools`, keyed by tool name.
      Tools without `mcpServer` are omitted.
    '';
  };
}
