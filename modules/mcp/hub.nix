# Need mcp-server-nix as overlays, NOT module.
# Because module generates json file on build, so it's not possible to use it as Nix home-manager configuration.

{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.types;
let
  cfg = config.my.home.mcp;

  # Generate mcp-remote-group script for each server
  mcp-remote-group-scripts = map (server:
    pkgs.writeShellScriptBin "mcp-remote-group-${server.name}" ''
      ${pkgs.mcp-server-remote}/bin/mcp-remote \
        http://${server.host}:${builtins.toString server.port}/v0/groups/''${1:-input group}/mcp \
        --allow-http
    ''
  ) cfg.hub.client.servers;
in
{
  options.my.home.mcp.hub.client = {
    enable = mkEnableOption "Enable MCP client for MCP Hub";
    servers = mkOption {
      description = "List of MCP hub servers";
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            description = "Name of the server";
            type = types.str;
          };
          host = mkOption {
            description = "Host of MCP hub";
            type = types.str;
            default = "127.0.0.1";
          };
          port = mkOption {
            description = "Port number of MCP hub client";
            type = types.port;
            default = 3001;
          };
        };
      });
      default = [
        {
          name = "default";
          host = "127.0.0.1";
          port = 3001;
        }
      ];
    };
  };

  config = lib.mkIf config.my.home.mcp.hub.client.enable {
    # For CLI
    home.packages = mcp-remote-group-scripts;
  };
}
