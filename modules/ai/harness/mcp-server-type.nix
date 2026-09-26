# Option type for a single stdio MCP server.
#
# Kept in a plain (non-module) file so both `harness/tools` (option
# declaration) and `harness/mcp` (derived registry) can import it.
{ lib, ... }:

lib.types.submodule {
  options = {
    command = lib.mkOption {
      type = lib.types.str;
      description = "Executable that speaks MCP over stdio.";
    };
    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Arguments passed to `command`.";
    };
    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables set for the server process.";
    };
    envKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Names of environment variables inherited from the agent process.";
    };
    timeout = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Per tool call timeout in seconds.";
    };
    displayName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Human readable name shown by the agent. Defaults to the tool name.";
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether agents register the server in their default session.";
    };
  };
}
