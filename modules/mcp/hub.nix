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

  mcp-serer-remote-group = pkgs.writeShellScriptBin "mcp-remote-group" ''
    ${pkgs.mcp-server-remote}/bin/mcp-remote \
      http://${cfg.hub.client.host}:${builtins.toString cfg.hub.client.port}/v0/groups/''${1:-input group}/mcp \
      --allow-http
  '';
in
{
  options.my.home.mcp.hub.client = {
    enable = mkEnableOption "Enable MCP client for MCP Hub";
    host = mkOption {
      description = "Host of MCP hub";
      type = str;
      default = "127.0.0.1";
    };
    port = mkOption {
      description = "Port number of MCP hub client";
      type = number;
      default = 3001;
    };
  };

  config = lib.mkIf config.my.home.mcp.hub.client.enable {
    # For CLI
    home.packages = [
      mcp-serer-remote-group
    ];
  };
}
